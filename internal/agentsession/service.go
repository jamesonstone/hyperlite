package agentsession

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"
)

type ServiceOptions struct {
	SocketPath   string
	Home         string
	BridgePath   string
	Environment  map[string]string
	DisableCodex bool
	Now          func() time.Time
}

type inboundEvent struct {
	event Event
	conn  net.Conn
}

type pendingResponse struct {
	sessionID string
	conn      net.Conn
}

type pendingClosure struct {
	requestID string
	conn      net.Conn
}

type safeEncoder struct {
	mu      sync.Mutex
	encoder *json.Encoder
}

func (e *safeEncoder) encode(value any) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.encoder.Encode(value)
}

func RunService(ctx context.Context, in io.Reader, out, errOut io.Writer, options ServiceOptions) error {
	serviceCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	if options.Now == nil {
		options.Now = func() time.Time { return time.Now().UTC() }
	}
	if options.SocketPath == "" {
		options.SocketPath = RuntimeSocketPath(serviceEnvironment(options))
	}
	listener, err := PrepareRuntimeSocket(options.SocketPath)
	if err != nil {
		return err
	}
	defer func() {
		_ = listener.Close()
		_ = os.Remove(options.SocketPath)
	}()
	store := NewStore()
	emitter := &safeEncoder{encoder: json.NewEncoder(out)}
	store.SetIntegrations(DetectIntegrations(options.Home, options.BridgePath))
	if err := emitter.encode(store.Snapshot(options.Now())); err != nil {
		return fmt.Errorf("emit initial agent snapshot: %w", err)
	}
	events := make(chan inboundEvent)
	actions := make(chan ActionRequest)
	closedResponses := make(chan pendingClosure)
	readErrors := make(chan error, 2)
	go acceptEvents(serviceCtx, listener, events, readErrors)
	go readActions(serviceCtx, in, actions, readErrors)
	if !options.DisableCodex {
		go func() {
			err := MonitorCodex(serviceCtx, serviceEnvironment(options), func(event Event) {
				select {
				case events <- inboundEvent{event: event}:
				case <-serviceCtx.Done():
				}
			})
			if err != nil {
				sendReadError(serviceCtx, readErrors, err)
			}
		}()
	}
	pending := make(map[string]pendingResponse)
	watchedRollouts := make(map[string]struct{})
	routing := loadRoutingMap(options, errOut)
	var timer *time.Timer
	var deadline <-chan time.Time
	resetTimer := func() {
		if timer != nil {
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
		}
		next, ok := store.NextDeadline()
		if !ok {
			timer, deadline = nil, nil
			return
		}
		delay := time.Until(next)
		if delay < 0 {
			delay = 0
		}
		timer = time.NewTimer(delay)
		deadline = timer.C
	}
	defer closePending(pending)
	for {
		select {
		case <-serviceCtx.Done():
			return nil
		case received := <-events:
			event := received.event
			if event.Provider == "codex" && event.RolloutPath != "" {
				if safePath, pathErr := SafeCodexRolloutPath(event.RolloutPath, options.Home); pathErr == nil {
					if _, exists := watchedRollouts[safePath]; !exists && len(watchedRollouts) < maxCodexRolloutWatches {
						watchedRollouts[safePath] = struct{}{}
						startRolloutWatch(serviceCtx, safePath, event, events, readErrors)
					}
				}
			}
			if event.rolloutHint {
				continue
			}
			key := Identity(event.Provider, event.SessionID)
			if existing, ok := routing[key]; ok {
				event.Routing = mergeRouting(existing.Routing, event.Routing, event.WorkspacePath)
			}
			snapshot, changed := store.Apply(event, options.Now())
			if event.ExpectsResponse && event.RequestID != "" && received.conn != nil &&
				snapshotHasAction(snapshot, key, event.RequestID) {
				if previous, exists := pending[event.RequestID]; exists {
					_ = previous.conn.Close()
				}
				pending[event.RequestID] = pendingResponse{sessionID: Identity(event.Provider, event.SessionID), conn: received.conn}
				go watchPendingClosure(serviceCtx, event.RequestID, received.conn, closedResponses)
			} else if received.conn != nil {
				_ = json.NewEncoder(received.conn).Encode(HookDecision{})
				_ = received.conn.Close()
			}
			if changed {
				routing[key] = RoutingRecord{Provider: event.Provider, Profile: event.Profile,
					SessionID: event.SessionID, Routing: snapshotRouting(snapshot, key), LastSeen: event.OccurredAt}
				saveRoutingMap(options, routing, errOut)
				if err := emitter.encode(snapshot); err != nil {
					return err
				}
			}
			resetTimer()
		case request := <-actions:
			result := ActionResult{Schema: ActionResultSchema, SessionID: request.SessionID,
				RequestID: request.RequestID, Action: request.Action, Status: "rejected"}
			if _, err := store.ValidateAction(request); err != nil {
				result.Message = err.Error()
			} else if target, ok := pending[request.RequestID]; !ok || target.sessionID != request.SessionID {
				result.Message = "live provider response channel is unavailable"
			} else if err := json.NewEncoder(target.conn).Encode(HookDecision{
				RequestID: request.RequestID, Action: request.Action, Answers: request.Answers,
			}); err != nil {
				result.Message = "provider response channel closed"
				_ = target.conn.Close()
				delete(pending, request.RequestID)
			} else {
				_ = target.conn.Close()
				delete(pending, request.RequestID)
				result.Status = "submitted"
				snapshot := store.ResolveAction(request, options.Now())
				if err := emitter.encode(snapshot); err != nil {
					return err
				}
				resetTimer()
			}
			if err := emitter.encode(result); err != nil {
				return err
			}
		case closed := <-closedResponses:
			if target, ok := pending[closed.requestID]; ok && target.conn == closed.conn {
				delete(pending, closed.requestID)
				_ = target.conn.Close()
				if snapshot, changed := store.CancelAction(target.sessionID, closed.requestID, options.Now()); changed {
					if err := emitter.encode(snapshot); err != nil {
						return err
					}
					resetTimer()
				}
			}
		case <-deadline:
			if snapshot, changed := store.Expire(options.Now()); changed {
				if err := emitter.encode(snapshot); err != nil {
					return err
				}
			}
			resetTimer()
		case readErr := <-readErrors:
			if readErr == io.EOF {
				return nil
			}
			if readErr != nil && readErr != io.EOF {
				_, _ = fmt.Fprintf(errOut, "agent session transport unavailable: %v\n", readErr)
			}
		}
	}
}

func acceptEvents(ctx context.Context, listener net.Listener, output chan<- inboundEvent, errors chan<- error) {
	for {
		connection, err := listener.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				sendReadError(ctx, errors, err)
				return
			}
		}
		go decodeEvent(ctx, connection, output)
	}
}

func decodeEvent(ctx context.Context, connection net.Conn, output chan<- inboundEvent) {
	_ = connection.SetReadDeadline(time.Now().Add(2 * time.Second))
	var event Event
	decoder := json.NewDecoder(io.LimitReader(connection, MaxHookPayload+1))
	if err := decoder.Decode(&event); err != nil || event.Schema != EventSchema {
		_ = connection.Close()
		return
	}
	_ = connection.SetDeadline(time.Time{})
	select {
	case output <- inboundEvent{event: event, conn: connection}:
	case <-ctx.Done():
		_ = connection.Close()
	}
}

func readActions(ctx context.Context, input io.Reader, output chan<- ActionRequest, errors chan<- error) {
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), MaxHookPayload)
	for scanner.Scan() {
		var request ActionRequest
		if err := json.Unmarshal(scanner.Bytes(), &request); err != nil {
			continue
		}
		select {
		case output <- request:
		case <-ctx.Done():
			return
		}
	}
	if err := scanner.Err(); err != nil {
		sendReadError(ctx, errors, err)
	} else {
		sendReadError(ctx, errors, io.EOF)
	}
}

func closePending(values map[string]pendingResponse) {
	for _, value := range values {
		_ = value.conn.Close()
	}
}
