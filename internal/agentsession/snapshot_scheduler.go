package agentsession

import "time"

const ordinarySnapshotInterval = 250 * time.Millisecond

type SnapshotScheduler struct {
	lastEmit time.Time
	pending  *Snapshot
}

func (s *SnapshotScheduler) RecordInitial(now time.Time) { s.lastEmit = now }

func (s *SnapshotScheduler) Submit(snapshot Snapshot, immediate bool, now time.Time) (*Snapshot, bool) {
	if immediate || s.lastEmit.IsZero() || now.Sub(s.lastEmit) >= ordinarySnapshotInterval {
		s.lastEmit = now
		s.pending = nil
		return &snapshot, true
	}
	pending := snapshot
	s.pending = &pending
	return nil, false
}

func (s *SnapshotScheduler) Due(now time.Time) (*Snapshot, bool) {
	if s.pending == nil || now.Before(s.lastEmit.Add(ordinarySnapshotInterval)) {
		return nil, false
	}
	value := *s.pending
	s.pending = nil
	s.lastEmit = now
	return &value, true
}

func (s *SnapshotScheduler) NextDeadline() (time.Time, bool) {
	if s.pending == nil {
		return time.Time{}, false
	}
	return s.lastEmit.Add(ordinarySnapshotInterval), true
}

func immediateSessionTransition(event Event) bool {
	return event.Phase.NeedsAttention() || event.Phase == PhaseError || safeAction(event) != nil
}
