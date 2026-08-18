package agentsession

import "time"

type watcherReporter struct {
	last     time.Time
	pending  int
	dirty    bool
	timer    *time.Timer
	deadline <-chan time.Time
	emit     func(int)
	interval time.Duration
}

func newWatcherReporter(emit func(int)) *watcherReporter {
	return &watcherReporter{emit: emit, interval: ordinarySnapshotInterval}
}

func (r *watcherReporter) submit(value int, now time.Time) {
	if r.emit == nil {
		return
	}
	if r.last.IsZero() || now.Sub(r.last) >= r.interval {
		r.emit(value)
		r.last = now
		r.dirty = false
		r.stopTimer()
		return
	}
	r.pending = value
	r.dirty = true
	if r.timer == nil {
		delay := r.last.Add(r.interval).Sub(now)
		if delay < 0 {
			delay = 0
		}
		r.timer = time.NewTimer(delay)
		r.deadline = r.timer.C
	}
}

func (r *watcherReporter) flush(now time.Time) {
	if r.dirty && r.emit != nil {
		r.emit(r.pending)
		r.last = now
	}
	r.dirty = false
	r.stopTimer()
}

func (r *watcherReporter) stop() { r.stopTimer() }

func (r *watcherReporter) stopTimer() {
	if r.timer != nil {
		r.timer.Stop()
	}
	r.timer = nil
	r.deadline = nil
}
