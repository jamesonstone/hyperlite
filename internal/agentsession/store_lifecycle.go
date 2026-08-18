package agentsession

import "time"

func nonzeroTime(now time.Time) time.Time {
	if now.IsZero() {
		return time.Now().UTC()
	}
	return now
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

func (s *Store) Expire(now time.Time) (Snapshot, bool) {
	snapshot, removed := s.ExpireWithIDs(now)
	return snapshot, len(removed) > 0
}

func (s *Store) ExpireWithIDs(now time.Time) (Snapshot, []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now = nonzeroTime(now)
	removed := make([]string, 0)
	for id, session := range s.sessions {
		if session.NeedsAttention() {
			continue
		}
		age := now.Sub(session.UpdatedAt)
		if (session.Phase == PhaseCompleted && age >= completedRetention) || age >= idleRetention {
			delete(s.sessions, id)
			removed = append(removed, id)
		}
	}
	if len(removed) > 0 {
		s.generation++
	}
	return s.snapshotLocked(now), removed
}

func (s *Store) Remove(id string, now time.Time) (Snapshot, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now = nonzeroTime(now)
	if _, ok := s.sessions[id]; !ok {
		return s.snapshotLocked(now), false
	}
	delete(s.sessions, id)
	s.generation++
	return s.snapshotLocked(now), true
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
	now = nonzeroTime(now)
	return s.snapshotLocked(now)
}

func (s *Store) Has(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.sessions[id]
	return ok
}

func (s *Store) Session(id string) (Session, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	value, ok := s.sessions[id]
	return cloneSession(value), ok
}

func (s *Store) Transitions() []PhaseTransition {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]PhaseTransition{}, s.transitions...)
}

func (s *Store) recordTransitionLocked(previous, current Session, event Event) {
	if previous.Phase == current.Phase {
		return
	}
	s.transitions = append(s.transitions, PhaseTransition{
		Timestamp: current.UpdatedAt, Provider: current.Provider, SessionID: current.SessionID,
		Source: event.Source, OldPhase: previous.Phase, NewPhase: current.Phase,
		Reason: boundedReason(event.ReasonCode, event.Event),
	})
	if len(s.transitions) > maxPhaseTransitions {
		s.transitions = s.transitions[len(s.transitions)-maxPhaseTransitions:]
	}
}

func (s *Store) evictForAdmissionLocked() bool {
	var candidate string
	var oldest time.Time
	for id, session := range s.sessions {
		if session.NeedsAttention() {
			continue
		}
		if candidate == "" || session.UpdatedAt.Before(oldest) {
			candidate, oldest = id, session.UpdatedAt
		}
	}
	if candidate == "" {
		return false
	}
	delete(s.sessions, candidate)
	return true
}

func boundedReason(primary, fallback string) string {
	value := firstNonempty(primary, fallback, "state_changed")
	runes := []rune(value)
	if len(runes) > 64 {
		return string(runes[:64])
	}
	return value
}
