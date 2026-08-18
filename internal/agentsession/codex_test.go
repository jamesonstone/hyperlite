package agentsession

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

func TestCodexMonitorUsesStdioAndDiscoversNotLoadedRollouts(t *testing.T) {
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
	var events []Event
	err := MonitorCodex(ctx, map[string]string{"PATH": directory, "HOME": directory}, func(event Event) {
		events = append(events, event)
	})
	if err != nil {
		t.Fatalf("monitor Codex: %v", err)
	}
	if len(events) != 3 {
		t.Fatalf("events = %#v", events)
	}
	if events[0].SessionID != "active-1" || events[0].Phase != PhaseWaitingApproval {
		t.Fatalf("active event = %#v", events[0])
	}
	if !events[1].rolloutHint || events[1].SessionID != "stored-1" ||
		events[1].RolloutPath != "/tmp/stored.jsonl" || events[1].Phase != "" {
		t.Fatalf("rollout discovery = %#v", events[1])
	}
	if events[2].Phase != PhaseIdle {
		t.Fatalf("status notification = %#v", events[2])
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
