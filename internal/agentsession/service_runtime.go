package agentsession

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"reflect"
	"time"
)

type sessionRuntime struct {
	ctx             context.Context
	options         ServiceOptions
	store           *Store
	emitter         *safeEncoder
	health          *HealthState
	gate            *VisibilityGate
	scheduler       *SnapshotScheduler
	routing         map[string]RoutingRecord
	pending         map[string]pendingResponse
	liveIDs         map[string]struct{}
	errOut          io.Writer
	rollouts        *RolloutManager
	codex           *CodexController
	liveness        *ProcessLiveness
	closedResponses chan<- pendingClosure
	processExits    chan<- string
	healthSignals   chan<- healthSignal
	selfTests       chan<- selfTestResult
	selfTestSlots   chan struct{}
}

func newSessionRuntime(
	ctx context.Context,
	options ServiceOptions,
	out, errOut io.Writer,
	integrations []IntegrationStatus,
) *sessionRuntime {
	return &sessionRuntime{
		ctx: ctx, options: options, store: NewStore(),
		emitter: &safeEncoder{encoder: json.NewEncoder(out)}, health: NewHealthState(integrations),
		gate: NewVisibilityGate(), scheduler: &SnapshotScheduler{},
		routing: loadRoutingMap(options, errOut), pending: make(map[string]pendingResponse),
		liveIDs: make(map[string]struct{}), errOut: errOut,
		selfTestSlots: make(chan struct{}, len(Profiles())),
	}
}

func (r *sessionRuntime) close() {
	if r.codex != nil {
		r.codex.Stop()
	}
	if r.liveness != nil {
		r.liveness.Close()
	}
	if r.rollouts != nil {
		r.rollouts.Wait()
	}
	closePending(r.pending)
}

func (r *sessionRuntime) handleEvent(received inboundEvent) error {
	event := received.event
	if event.Provider == "codex" && event.Source != SourceRollout &&
		event.RolloutPath != "" && r.rollouts != nil {
		admitted := r.rollouts.Admit(event)
		if event.rolloutHint {
			closeEventConnection(received.conn)
			if !admitted {
				return r.emitRejected("codex", "watcher_queue_full")
			}
			return nil
		}
		if !admitted {
			if err := r.emitRejected("codex", "watcher_queue_full"); err != nil {
				return err
			}
		}
	}
	id := Identity(event.Provider, event.SessionID)
	visible, publish, filtered := r.gate.Offer(event, r.store.Has(id), r.options.Now())
	if filtered {
		if r.rollouts != nil {
			r.rollouts.Release(id)
		}
		closeEventConnection(received.conn)
		return r.emitFiltered(event.Profile, 1)
	}
	if !publish {
		closeEventConnection(received.conn)
		return nil
	}
	event = visible
	now := r.options.Now()
	snapshot, changed := r.store.Apply(event, now)
	if event.Source != SourceRollout || event.rolloutCaughtUp {
		if health, healthChanged := r.health.Event(event, now); healthChanged {
			if err := r.emitter.encode(health); err != nil {
				return err
			}
		}
	}
	if event.Synthetic {
		closeEventConnection(received.conn)
		if !changed {
			return r.emitSelfTest(event.Profile, "failed", "store_rejected")
		}
		r.reconcileRemoved(snapshot)
		if err := r.emitSnapshot(snapshot, true); err != nil {
			return err
		}
		removed, removedSynthetic := r.store.Remove(id, now)
		if !removedSynthetic {
			return r.emitSelfTest(event.Profile, "failed", "store_rejected")
		}
		if err := r.emitSnapshot(removed, true); err != nil {
			return err
		}
		r.reconcileRemoved(removed)
		return r.emitSelfTest(event.Profile, "passed", "")
	}
	r.observeResponseChannel(event, received.conn, snapshot)
	actionRejected := safeAction(event) != nil && !snapshotHasAction(snapshot, id, event.RequestID)
	if received.conn != nil && !snapshotHasAction(snapshot, id, event.RequestID) {
		closeEventConnection(received.conn)
	}
	if !changed {
		if event.Source == SourceRollout && event.rolloutCaughtUp && !r.store.Has(id) && r.rollouts != nil {
			r.rollouts.Release(id)
		}
		if actionRejected {
			return r.emitRejected(event.Profile, "action_queue_full")
		}
		return nil
	}
	if r.liveness != nil {
		r.liveness.Observe(event)
	}
	r.reconcileRemoved(snapshot)
	if r.updateRouting(event, snapshot) {
		saveRoutingMap(r.options, r.routing, r.errOut)
	}
	if event.Phase == PhaseEnded {
		r.releaseSession(id)
	}
	if err := r.emitSnapshot(snapshot, immediateSessionTransition(event)); err != nil {
		return err
	}
	if actionRejected {
		return r.emitRejected(event.Profile, "action_queue_full")
	}
	return nil
}

func (r *sessionRuntime) observeResponseChannel(event Event, conn net.Conn, snapshot Snapshot) {
	if !event.ExpectsResponse || event.RequestID == "" || conn == nil {
		return
	}
	id := Identity(event.Provider, event.SessionID)
	if !snapshotHasAction(snapshot, id, event.RequestID) {
		return
	}
	key := responseKey(id, event.RequestID)
	if previous, exists := r.pending[key]; exists {
		_ = previous.conn.Close()
	}
	r.pending[key] = pendingResponse{sessionID: id, requestID: event.RequestID, provider: event.Provider, conn: conn}
	go watchPendingClosure(r.ctx, key, conn, r.closedResponses)
}

func (r *sessionRuntime) emitSnapshot(snapshot Snapshot, immediate bool) error {
	value, emit := r.scheduler.Submit(snapshot, immediate, r.options.Now())
	if !emit {
		return nil
	}
	return r.emitter.encode(*value)
}

func (r *sessionRuntime) updateRouting(event Event, snapshot Snapshot) bool {
	if event.Synthetic {
		return false
	}
	id := Identity(event.Provider, event.SessionID)
	seen := nonzeroObservedTime(event.OccurredAt, r.options.Now())
	next := RoutingRecord{Provider: event.Provider, Profile: event.Profile,
		SessionID: event.SessionID, Routing: snapshotRouting(snapshot, id), LastSeen: seen}
	previous, exists := r.routing[id]
	r.routing[id] = next
	return !exists || previous.Provider != next.Provider || previous.Profile != next.Profile ||
		!reflect.DeepEqual(previous.Routing, next.Routing) || seen.Sub(previous.LastSeen) >= time.Minute
}

func (r *sessionRuntime) reconcileRemoved(snapshot Snapshot) {
	next := make(map[string]struct{}, len(snapshot.Sessions))
	for _, session := range snapshot.Sessions {
		next[session.ID] = struct{}{}
	}
	for id := range r.liveIDs {
		if _, exists := next[id]; !exists {
			r.releaseSession(id)
		}
	}
	r.liveIDs = next
}

func (r *sessionRuntime) releaseSession(id string) {
	if r.rollouts != nil {
		r.rollouts.Release(id)
	}
	if r.liveness != nil {
		r.liveness.Remove(id)
	}
	r.gate.Remove(id)
	for key, response := range r.pending {
		if response.sessionID == id {
			_ = response.conn.Close()
			delete(r.pending, key)
		}
	}
}

func closeEventConnection(connection net.Conn) {
	if connection == nil {
		return
	}
	_ = json.NewEncoder(connection).Encode(HookDecision{})
	_ = connection.Close()
}

func responseKey(sessionID, requestID string) string { return sessionID + "\x00" + requestID }

func (r *sessionRuntime) handleProcessExit(id string) error {
	session, ok := r.store.Session(id)
	if !ok {
		return nil
	}
	return r.handleEvent(inboundEvent{event: Event{
		Schema: EventSchema, Provider: session.Provider, Profile: session.Profile,
		SessionID: session.SessionID, Event: "process_exit", Phase: PhaseEnded,
		Source: SourceHook, OccurredAt: r.options.Now(), ReasonCode: "process_exit",
	}})
}
