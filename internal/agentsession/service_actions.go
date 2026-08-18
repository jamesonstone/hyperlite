package agentsession

import (
	"encoding/json"
)

func (r *sessionRuntime) handleInput(input serviceInput) error {
	if input.action != nil {
		return r.handleAction(*input.action)
	}
	if input.control != nil {
		return r.handleControl(*input.control)
	}
	return nil
}

func (r *sessionRuntime) handleAction(request ActionRequest) error {
	result := ActionResult{Schema: ActionResultSchema, SessionID: request.SessionID,
		RequestID: request.RequestID, Action: request.Action, Status: "rejected"}
	_, err := r.store.ValidateAction(request)
	if err != nil {
		result.Message = err.Error()
		return r.emitter.encode(result)
	}
	key := responseKey(request.SessionID, request.RequestID)
	target, ok := r.pending[key]
	if !ok || target.sessionID != request.SessionID ||
		(request.Provider != "" && target.provider != request.Provider) {
		result.Message = "live provider response channel is unavailable"
		return r.emitter.encode(result)
	}
	if err := json.NewEncoder(target.conn).Encode(HookDecision{
		RequestID: request.RequestID, Action: request.Action, Answers: request.Answers,
	}); err != nil {
		result.Message = "provider response channel closed"
		_ = target.conn.Close()
		delete(r.pending, key)
		return r.emitter.encode(result)
	}
	_ = target.conn.Close()
	delete(r.pending, key)
	result.Status = "submitted"
	snapshot := r.store.ResolveAction(request, r.options.Now())
	r.reconcileRemoved(snapshot)
	if err := r.emitSnapshot(snapshot, true); err != nil {
		return err
	}
	return r.emitter.encode(result)
}

func (r *sessionRuntime) handleControl(request ControlRequest) error {
	switch request.Operation {
	case ControlForegroundRefresh, ControlManualRefresh:
		if r.rollouts != nil {
			r.rollouts.Refresh()
		}
		if r.codex != nil {
			r.codex.RequestRefresh()
		}
	case ControlIntegrationTest:
		if request.Profile == "codex" && r.codex != nil {
			r.codex.RequestRefresh()
		}
		select {
		case r.selfTestSlots <- struct{}{}:
		default:
			return r.emitSelfTest(request.Profile, "failed", "self_test_busy")
		}
		go func() {
			defer func() { <-r.selfTestSlots }()
			err := runIntegrationSelfTest(r.ctx, r.options.SocketPath, request)
			result := selfTestResult{profile: request.Profile, request: request.RequestID, err: err}
			select {
			case r.selfTests <- result:
			case <-r.ctx.Done():
			}
		}()
	}
	return nil
}

func (r *sessionRuntime) handleClosedResponse(closed pendingClosure) error {
	target, ok := r.pending[closed.key]
	if !ok || target.conn != closed.conn {
		return nil
	}
	delete(r.pending, closed.key)
	_ = target.conn.Close()
	snapshot, changed := r.store.CancelAction(target.sessionID, target.requestID, r.options.Now())
	if !changed {
		return nil
	}
	r.reconcileRemoved(snapshot)
	return r.emitSnapshot(snapshot, true)
}
