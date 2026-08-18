package agentsession

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestStartRolloutWatchEmitsWithoutBlockingCaller(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rollout.jsonl")
	data := []byte(`{"timestamp":"2026-08-17T12:00:00Z","type":"session_meta","payload":{"id":"thread-1"}}` + "\n")
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := make(chan inboundEvent)
	errors := make(chan error)
	returned := make(chan struct{})
	go func() {
		startRolloutWatch(ctx, path, "fallback", events, errors)
		close(returned)
	}()
	select {
	case <-returned:
	case <-time.After(time.Second):
		t.Fatal("startRolloutWatch blocked on its initial emit")
	}
	select {
	case event := <-events:
		if event.event.SessionID != "thread-1" {
			t.Fatalf("initial rollout event = %#v", event.event)
		}
	case <-time.After(time.Second):
		t.Fatal("initial rollout event was not emitted")
	}
}

func TestSendReadErrorStopsAfterCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	done := make(chan struct{})
	go func() {
		sendReadError(ctx, make(chan error), context.Canceled)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("error sender blocked after cancellation")
	}
}
