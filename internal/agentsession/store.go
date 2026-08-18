package agentsession

import (
	"errors"
	"reflect"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	completedRetention = 10 * time.Minute
	idleRetention      = 30 * time.Minute
)

var (
	ErrUnknownSession = errors.New("unknown agent session")
	ErrStaleAction    = errors.New("agent session action is stale")
	ErrUnsupported    = errors.New("agent session action is unsupported")
	ErrInvalidAction  = errors.New("agent session action payload is invalid")
)

type Store struct {
	mu           sync.Mutex
	sessions     map[string]Session
	integrations []IntegrationStatus
	transitions  []PhaseTransition
	generation   uint64
}

func NewStore() *Store {
	return &Store{sessions: make(map[string]Session)}
}

func Identity(provider, sessionID string) string {
	return strings.ToLower(strings.TrimSpace(provider)) + ":" + strings.TrimSpace(sessionID)
}

func (s *Store) SetIntegrations(values []IntegrationStatus) Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	values = append([]IntegrationStatus{}, values...)
	if !reflect.DeepEqual(s.integrations, values) {
		s.integrations = values
		s.generation++
	}
	return s.snapshotLocked(time.Now().UTC())
}

func (s *Store) Apply(event Event, now time.Time) (Snapshot, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now = nonzeroTime(now)
	event = normalizeEvent(event, now)
	if event.Provider == "" || event.SessionID == "" {
		return s.snapshotLocked(now), false
	}
	id := Identity(event.Provider, event.SessionID)
	current, exists := s.sessions[id]
	if !exists && newEventExpired(event, now) {
		return s.snapshotLocked(now), false
	}
	if exists && staleAgainst(current, event) {
		return s.snapshotLocked(now), false
	}
	if !exists && len(s.sessions) >= maxSessions && !s.evictForAdmissionLocked() {
		return s.snapshotLocked(now), false
	}
	updated := applyEvent(current, exists, id, event)
	if exists && sameSessionProjection(current, updated) {
		return s.snapshotLocked(now), false
	}
	updated.Revision = current.Revision + 1
	for index := range updated.Actions {
		if updated.Actions[index].Revision == 0 {
			updated.Actions[index].Revision = updated.Revision
		}
	}
	s.sessions[id] = updated
	s.recordTransitionLocked(current, updated, event)
	s.generation++
	return s.snapshotLocked(now), true
}

func normalizeEvent(event Event, now time.Time) Event {
	event.Provider = strings.ToLower(strings.TrimSpace(event.Provider))
	event.Profile = strings.TrimSpace(event.Profile)
	event.SessionID = strings.TrimSpace(event.SessionID)
	event.ParentID = strings.TrimSpace(event.ParentID)
	event.Event = strings.TrimSpace(event.Event)
	event.ReasonCode = boundedReason(event.ReasonCode, event.Event)
	if event.Source == "" {
		event.Source = SourceHook
	}
	if event.OccurredAt.IsZero() || event.OccurredAt.After(now.Add(time.Minute)) {
		event.OccurredAt = now
	}
	if event.Phase == "" {
		event.Phase = phaseForEvent(event.Event)
	}
	return event
}

func staleAgainst(current Session, event Event) bool {
	if len(current.Actions) > 0 && event.Source.Authority() < current.Source.Authority() {
		return true
	}
	if event.OccurredAt.Before(current.UpdatedAt) {
		return event.Source.Authority() <= current.Source.Authority()
	}
	return event.OccurredAt.Equal(current.UpdatedAt) &&
		event.Source.Authority() < current.Source.Authority()
}

func applyEvent(current Session, exists bool, id string, event Event) Session {
	if !exists {
		current = Session{
			ID: id, Provider: event.Provider, Profile: event.Profile,
			SessionID: event.SessionID, Phase: PhaseStarting,
			CreatedAt: event.OccurredAt, Messages: []Message{}, Actions: []PendingAction{},
		}
	}
	current.Profile = firstNonempty(event.Profile, current.Profile)
	current.ParentID = firstNonempty(event.ParentID, current.ParentID)
	current.Source = event.Source
	current.Phase = event.Phase
	current.UpdatedAt = event.OccurredAt
	current.Routing = mergeRouting(current.Routing, event.Routing, event.WorkspacePath)
	current.Project = projectName(current.Routing.WorkspacePath, current.Provider)
	current.Title = BoundDisplayText(firstNonempty(event.Title, current.Title, current.Project), 240)
	current.OpenInClient = routingAvailable(current.Routing)
	current.Synthetic = event.Synthetic
	applyEventContent(&current, event)
	if action := safeAction(event); action != nil {
		current.Actions, _ = upsertPendingAction(current.Actions, *action)
	} else if terminalPhase(event.Phase) {
		current.Actions = []PendingAction{}
	}
	if current.Actions == nil {
		current.Actions = []PendingAction{}
	}
	return current
}

func applyEventContent(current *Session, event Event) {
	if role := displayRole(event.MessageRole); role != "" {
		text := BoundDisplayText(event.Message, maxMessageRunes)
		if text != "" {
			current.Messages = append(current.Messages, Message{Role: role, Text: text})
		}
	}
	if event.Source == SourceRollout && len(event.Messages) > 0 {
		current.Messages = []Message{}
	}
	for _, message := range event.Messages {
		role := displayRole(message.Role)
		text := BoundDisplayText(message.Text, maxMessageRunes)
		if role != "" && text != "" {
			current.Messages = append(current.Messages, Message{Role: role, Text: text})
		}
	}
	if len(current.Messages) > maxMessages {
		current.Messages = current.Messages[len(current.Messages)-maxMessages:]
	}
	if current.Messages == nil {
		current.Messages = []Message{}
	}
	if event.LatestResult != "" {
		current.LatestResult = BoundDisplayText(event.LatestResult, maxResultRunes)
	}
}

func upsertPendingAction(values []PendingAction, incoming PendingAction) ([]PendingAction, bool) {
	for index := range values {
		if values[index].RequestID != incoming.RequestID {
			continue
		}
		incoming.Revision = values[index].Revision
		if reflect.DeepEqual(values[index], incoming) {
			return values, false
		}
		incoming.Revision = 0
		result := append([]PendingAction{}, values...)
		result[index] = incoming
		return result, true
	}
	if len(values) >= maxPendingActions {
		return values, false
	}
	return append(append([]PendingAction{}, values...), incoming), true
}

func sameSessionProjection(left, right Session) bool {
	left.Revision, right.Revision = 0, 0
	return reflect.DeepEqual(left, right)
}

func terminalPhase(phase Phase) bool {
	return phase == PhaseCompleted || phase == PhaseError || phase == PhaseEnded
}

func (s *Store) snapshotLocked(now time.Time) Snapshot {
	values := make([]Session, 0, len(s.sessions))
	for _, session := range s.sessions {
		values = append(values, cloneSession(session))
	}
	sort.Slice(values, func(i, j int) bool { return sessionBefore(values[i], values[j]) })
	return Snapshot{Schema: SnapshotSchema, Generation: s.generation, GeneratedAt: now,
		Sessions: values, Integrations: append([]IntegrationStatus{}, s.integrations...)}
}

func sessionBefore(a, b Session) bool {
	if a.NeedsAttention() != b.NeedsAttention() {
		return a.NeedsAttention()
	}
	if a.Phase.Active() != b.Phase.Active() {
		return a.Phase.Active()
	}
	if !a.UpdatedAt.Equal(b.UpdatedAt) {
		return a.UpdatedAt.After(b.UpdatedAt)
	}
	return a.ID < b.ID
}
