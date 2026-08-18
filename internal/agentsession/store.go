package agentsession

import (
	"errors"
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
	s.integrations = append([]IntegrationStatus(nil), values...)
	s.generation++
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
	updated := applyEvent(current, exists, id, event)
	s.sessions[id] = updated
	s.generation++
	return s.snapshotLocked(now), true
}

func newEventExpired(event Event, now time.Time) bool {
	if event.Phase.NeedsAttention() || safeAction(event) != nil || event.ExpectsResponse {
		return false
	}
	retention := idleRetention
	if event.Phase == PhaseCompleted {
		retention = completedRetention
	}
	return now.Sub(event.OccurredAt) >= retention
}

func normalizeEvent(event Event, now time.Time) Event {
	event.Provider = strings.ToLower(strings.TrimSpace(event.Provider))
	event.Profile = strings.TrimSpace(event.Profile)
	event.SessionID = strings.TrimSpace(event.SessionID)
	event.ParentID = strings.TrimSpace(event.ParentID)
	event.Event = strings.TrimSpace(event.Event)
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
	if current.Action != nil && event.Source.Authority() < current.Source.Authority() {
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
			CreatedAt: event.OccurredAt, Messages: []Message{},
		}
	}
	current.Profile = firstNonempty(event.Profile, current.Profile)
	current.ParentID = firstNonempty(event.ParentID, current.ParentID)
	current.Source = event.Source
	current.Phase = event.Phase
	current.UpdatedAt = event.OccurredAt
	current.Revision++
	current.Routing = mergeRouting(current.Routing, event.Routing, event.WorkspacePath)
	current.Project = projectName(current.Routing.WorkspacePath, current.Provider)
	current.Title = BoundDisplayText(firstNonempty(event.Title, current.Title, current.Project), 240)
	current.OpenInClient = routingAvailable(current.Routing)
	if role := displayRole(event.MessageRole); role != "" {
		text := BoundDisplayText(event.Message, maxMessageRunes)
		if text != "" {
			current.Messages = append(current.Messages, Message{Role: role, Text: text})
			if len(current.Messages) > maxMessages {
				current.Messages = current.Messages[len(current.Messages)-maxMessages:]
			}
		}
	}
	if event.Source == SourceRollout && len(event.Messages) > 0 {
		current.Messages = nil
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
	if event.LatestResult != "" {
		current.LatestResult = BoundDisplayText(event.LatestResult, maxResultRunes)
	}
	current.Action = safeAction(event)
	return current
}

func (s *Store) ValidateAction(request ActionRequest) (Session, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, ok := s.sessions[request.SessionID]
	if !ok {
		return Session{}, ErrUnknownSession
	}
	if request.Schema != ActionSchema || session.Revision != request.Revision ||
		session.Action == nil || session.Action.RequestID != request.RequestID {
		return Session{}, ErrStaleAction
	}
	if !actionAllowed(*session.Action, request.Action) {
		return Session{}, ErrUnsupported
	}
	if request.Action == "answer" && !validAnswers(request.Answers) {
		return Session{}, ErrInvalidAction
	}
	return cloneSession(session), nil
}

func (s *Store) ResolveAction(request ActionRequest, now time.Time) Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	now = nonzeroTime(now)
	session, ok := s.sessions[request.SessionID]
	if !ok || session.Action == nil || session.Action.RequestID != request.RequestID {
		return s.snapshotLocked(now)
	}
	session.Action = nil
	session.Revision++
	session.UpdatedAt = now
	if session.Phase.NeedsAttention() {
		session.Phase = PhaseProcessing
	}
	s.sessions[request.SessionID] = session
	s.generation++
	return s.snapshotLocked(now)
}

func (s *Store) CancelAction(sessionID, requestID string, now time.Time) (Snapshot, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now = nonzeroTime(now)
	session, ok := s.sessions[sessionID]
	if !ok || session.Action == nil || session.Action.RequestID != requestID {
		return s.snapshotLocked(now), false
	}
	session.Action = nil
	session.Revision++
	session.UpdatedAt = now
	if session.Phase.NeedsAttention() {
		session.Phase = PhaseIdle
	}
	s.sessions[sessionID] = session
	s.generation++
	return s.snapshotLocked(now), true
}

func nonzeroTime(now time.Time) time.Time {
	if now.IsZero() {
		return time.Now().UTC()
	}
	return now
}

func (s *Store) Expire(now time.Time) (Snapshot, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	changed := false
	for id, session := range s.sessions {
		if session.NeedsAttention() {
			continue
		}
		age := now.Sub(session.UpdatedAt)
		if (session.Phase == PhaseCompleted && age >= completedRetention) || age >= idleRetention {
			delete(s.sessions, id)
			changed = true
		}
	}
	if changed {
		s.generation++
	}
	return s.snapshotLocked(now), changed
}

func (s *Store) NextDeadline() (time.Time, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var next time.Time
	for _, session := range s.sessions {
		if session.NeedsAttention() {
			continue
		}
		deadline := session.UpdatedAt.Add(idleRetention)
		if session.Phase == PhaseCompleted {
			deadline = session.UpdatedAt.Add(completedRetention)
		}
		if next.IsZero() || deadline.Before(next) {
			next = deadline
		}
	}
	return next, !next.IsZero()
}

func (s *Store) Snapshot(now time.Time) Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.snapshotLocked(now)
}

func (s *Store) snapshotLocked(now time.Time) Snapshot {
	values := make([]Session, 0, len(s.sessions))
	for _, session := range s.sessions {
		values = append(values, cloneSession(session))
	}
	sort.Slice(values, func(i, j int) bool { return sessionBefore(values[i], values[j]) })
	return Snapshot{Schema: SnapshotSchema, Generation: s.generation, GeneratedAt: now,
		Sessions: values, Integrations: append([]IntegrationStatus(nil), s.integrations...)}
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
