package agentsession

import "time"

func (s *Store) ValidateAction(request ActionRequest) (Session, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, ok := s.sessions[request.SessionID]
	if !ok {
		return Session{}, ErrUnknownSession
	}
	if request.Schema != ActionSchema && request.Schema != ActionSchemaV1 {
		return Session{}, ErrStaleAction
	}
	if request.Schema == ActionSchema && request.Provider != session.Provider {
		return Session{}, ErrStaleAction
	}
	action, ok := actionByRequest(session.Actions, request.RequestID)
	expectedRevision := action.Revision
	if request.Schema == ActionSchemaV1 {
		expectedRevision = session.Revision
	}
	if !ok || expectedRevision != request.Revision {
		return Session{}, ErrStaleAction
	}
	if !actionAllowed(action, request.Action) {
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
	if !ok {
		return s.snapshotLocked(now)
	}
	updated, removed := removeAction(session.Actions, request.RequestID)
	if !removed {
		return s.snapshotLocked(now)
	}
	session.Actions = updated
	session.Revision++
	session.UpdatedAt = now
	if len(session.Actions) == 0 && session.Phase.NeedsAttention() {
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
	if !ok {
		return s.snapshotLocked(now), false
	}
	updated, removed := removeAction(session.Actions, requestID)
	if !removed {
		return s.snapshotLocked(now), false
	}
	session.Actions = updated
	session.Revision++
	session.UpdatedAt = now
	if len(session.Actions) == 0 && session.Phase.NeedsAttention() {
		session.Phase = PhaseIdle
	}
	s.sessions[sessionID] = session
	s.generation++
	return s.snapshotLocked(now), true
}

func actionByRequest(values []PendingAction, requestID string) (PendingAction, bool) {
	for _, action := range values {
		if action.RequestID == requestID {
			return action, true
		}
	}
	return PendingAction{}, false
}

func removeAction(values []PendingAction, requestID string) ([]PendingAction, bool) {
	for index, action := range values {
		if action.RequestID == requestID {
			result := append([]PendingAction{}, values[:index]...)
			result = append(result, values[index+1:]...)
			return result, true
		}
	}
	return values, false
}
