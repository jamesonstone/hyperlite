package agentsession

func (r *sessionRuntime) handleHealth(signal healthSignal) error {
	var value IntegrationHealth
	var changed bool
	switch signal.kind {
	case "connection":
		value, changed = r.health.Connection(signal.profile, signal.state, signal.code)
	case "ack":
		value, changed = r.health.Acknowledge(signal.profile, signal.at)
	case "watchers":
		value, changed = r.health.Watchers(signal.used)
	case "filtered":
		value, changed = r.health.Filtered(signal.profile, 1)
	case "rejected":
		value, changed = r.health.Rejected(signal.profile, signal.code)
	}
	if !changed {
		return nil
	}
	return r.emitter.encode(value)
}

func (r *sessionRuntime) emitFiltered(profile string, count uint64) error {
	value, changed := r.health.Filtered(firstNonempty(profile, "codex"), count)
	if !changed {
		return nil
	}
	return r.emitter.encode(value)
}

func (r *sessionRuntime) emitRejected(profile, code string) error {
	value, changed := r.health.Rejected(firstNonempty(profile, "codex"), code)
	if !changed {
		return nil
	}
	return r.emitter.encode(value)
}

func (r *sessionRuntime) emitSelfTest(profile, result, code string) error {
	value, changed := r.health.SelfTest(profile, result, code, r.options.Now())
	if !changed {
		return nil
	}
	return r.emitter.encode(value)
}
