package agentsession

import (
	"testing"
	"time"
)

func TestWatcherReporterCoalescesBurstAndSettlesWithoutTimer(t *testing.T) {
	var values []int
	reporter := newWatcherReporter(func(value int) { values = append(values, value) })
	defer reporter.stop()
	now := timeForTest()
	reporter.submit(1, now)
	reporter.submit(2, now.Add(10*time.Millisecond))
	reporter.submit(32, now.Add(20*time.Millisecond))
	if len(values) != 1 || values[0] != 1 || reporter.deadline == nil {
		t.Fatalf("watcher burst = values %#v deadline=%v", values, reporter.deadline != nil)
	}
	reporter.flush(now.Add(ordinarySnapshotInterval))
	if len(values) != 2 || values[1] != 32 || reporter.deadline != nil {
		t.Fatalf("watcher settle = values %#v deadline=%v", values, reporter.deadline != nil)
	}
}
