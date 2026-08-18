package agentsession

import "time"

func (r *sessionRuntime) nextDeadline() (time.Time, bool) {
	var next time.Time
	for _, source := range []func() (time.Time, bool){
		r.store.NextDeadline,
		r.gate.NextDeadline,
		r.scheduler.NextDeadline,
	} {
		candidate, ok := source()
		if ok && (next.IsZero() || candidate.Before(next)) {
			next = candidate
		}
	}
	return next, !next.IsZero()
}

func (r *sessionRuntime) handleDeadline() error {
	now := r.options.Now()
	events, filtered := r.gate.Due(now)
	if filtered > 0 {
		if err := r.emitFiltered("codex", uint64(filtered)); err != nil {
			return err
		}
	}
	for _, event := range events {
		if err := r.handleEvent(inboundEvent{event: event}); err != nil {
			return err
		}
	}
	snapshot, removed := r.store.ExpireWithIDs(now)
	if len(removed) > 0 {
		r.reconcileRemoved(snapshot)
		if err := r.emitSnapshot(snapshot, false); err != nil {
			return err
		}
	}
	if pending, ok := r.scheduler.Due(now); ok {
		return r.emitter.encode(*pending)
	}
	return nil
}
