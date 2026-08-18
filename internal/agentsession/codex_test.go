package agentsession

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

func TestCodexControllerUsesStdioAndDiscoversNotLoadedRollouts(t *testing.T) {
	directory := t.TempDir()
	executable := filepath.Join(directory, "codex")
	script := `#!/bin/sh
IFS= read -r initialize
printf '%s\n' '{"id":1,"result":{"userAgent":"test"}}'
IFS= read -r initialized
IFS= read -r list
printf '%s\n' '{"id":2,"result":{"data":[{"id":"active-1","name":"Active","cwd":"/tmp/project","status":{"type":"active","activeFlags":["waitingOnApproval"]}},{"id":"stored-1","name":"Stored","cwd":"/tmp/stored","path":"/tmp/stored.jsonl","status":{"type":"notLoaded"}}]}}'
printf '%s\n' '{"method":"thread/status/changed","params":{"threadId":"active-1","status":{"type":"idle"}}}'
`
	if err := os.WriteFile(executable, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	eventChannel := make(chan Event, 3)
	controller := NewCodexController(ctx, CodexControllerOptions{
		Environment: map[string]string{"PATH": directory, "HOME": directory},
		Emit:        func(event Event) { eventChannel <- event },
	})
	if err := controller.Refresh(ctx); err != nil {
		t.Fatalf("refresh Codex: %v", err)
	}
	events := make([]Event, 0, 3)
	for len(events) < 3 {
		select {
		case event := <-eventChannel:
			events = append(events, event)
		case <-time.After(time.Second):
			t.Fatal("Codex notification timed out")
		}
	}
	controller.Stop()
	if len(events) != 3 {
		t.Fatalf("events = %#v", events)
	}
	var approval, hint, idle bool
	for _, event := range events {
		approval = approval || (event.SessionID == "active-1" && event.Phase == PhaseWaitingApproval)
		hint = hint || (event.rolloutHint && event.SessionID == "stored-1" &&
			event.RolloutPath == "/tmp/stored.jsonl" && event.Phase == "")
		idle = idle || (event.SessionID == "active-1" && event.Phase == PhaseIdle)
	}
	if !approval || !hint || !idle {
		t.Fatalf("controller events = %#v", events)
	}
}

func TestMergeEnvironmentOverridesInheritedValues(t *testing.T) {
	merged := mergeEnvironment(
		[]string{"HOME=/inherited", "PATH=/bin", "PRESERVED=value"},
		map[string]string{"HOME": "/injected", "PATH": "/custom"},
	)
	for _, expected := range []string{"HOME=/injected", "PATH=/custom", "PRESERVED=value"} {
		if !slices.Contains(merged, expected) {
			t.Fatalf("merged environment missing %q: %#v", expected, merged)
		}
	}
	if slices.Contains(merged, "HOME=/inherited") || slices.Contains(merged, "PATH=/bin") {
		t.Fatalf("inherited value was not overridden: %#v", merged)
	}
}

func TestCodexStatusRequiresKnownRuntimeState(t *testing.T) {
	if _, ok := codexStatusEvent("thread", map[string]any{"type": "notLoaded"}, time.Now()); ok {
		t.Fatal("notLoaded status was treated as live")
	}
	event, ok := codexStatusEvent("thread", map[string]any{"type": "active", "activeFlags": []any{"waitingOnUserInput"}}, time.Now())
	if !ok || event.Phase != PhaseWaitingInput {
		t.Fatalf("unexpected active status: %#v", event)
	}
	if _, ok := codexThreadEvent(map[string]any{
		"id": "stored", "status": map[string]any{"type": "notLoaded"},
	}, time.Now()); ok {
		t.Fatal("notLoaded thread without a rollout path was discovered")
	}
}

func TestCodexThreadRecencyAcceptsNumericTimestamps(t *testing.T) {
	want := time.Date(2026, 8, 18, 12, 0, 0, 0, time.UTC)
	for _, value := range []any{float64(want.Unix()), float64(want.UnixMilli()), want.Format(time.RFC3339)} {
		got := firstTime(map[string]any{"updatedAt": value}, "updatedAt")
		if !got.Equal(want) {
			t.Fatalf("firstTime(%v) = %v want %v", value, got, want)
		}
	}
}
