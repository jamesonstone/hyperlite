package agentsession

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func TestRolloutManagerRefreshesExistingAndObservesAppend(t *testing.T) {
	home := t.TempDir()
	now := time.Now()
	directory := codexDateDirectory(home, now)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "rollout.jsonl")
	writeRollout(t, path, rolloutRow("session_meta", `{"id":"thread-1"}`),
		rolloutRow("event_msg", `{"type":"task_started"}`))
	ctx, cancel := context.WithCancel(context.Background())
	events := make(chan Event, 16)
	manager := StartRolloutManager(ctx, RolloutManagerOptions{
		Home: home, Emit: func(event Event) {
			select {
			case events <- event:
			default:
			}
		},
	})
	defer func() {
		cancel()
		manager.Wait()
	}()
	first := waitForRolloutEvent(t, events)
	if first.SessionID != "thread-1" || first.Phase != PhaseProcessing {
		t.Fatalf("initial event = %#v", first)
	}
	writeRollout(t, path, rolloutRow("session_meta", `{"id":"thread-1"}`),
		rolloutRow("event_msg", `{"type":"task_complete"}`))
	manager.Refresh()
	refreshed := waitForRolloutEvent(t, events)
	if refreshed.Phase != PhaseCompleted {
		t.Fatalf("refreshed event = %#v", refreshed)
	}
	if runtime.GOOS != "darwin" {
		return
	}
	time.Sleep(20 * time.Millisecond)
	appendRollout(t, path, rolloutRow("event_msg", `{"type":"task_started"}`))
	appended := waitForRolloutEvent(t, events)
	if appended.Phase != PhaseProcessing {
		t.Fatalf("appended event = %#v", appended)
	}
}

func waitForRolloutEvent(t *testing.T, events <-chan Event) Event {
	t.Helper()
	select {
	case event := <-events:
		return event
	case <-time.After(3 * time.Second):
		t.Fatal("rollout event timed out")
		return Event{}
	}
}
