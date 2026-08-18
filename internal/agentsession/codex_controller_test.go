package agentsession

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestCodexControllerPaginatesReusesAndStopsAfterQuiet(t *testing.T) {
	directory := t.TempDir()
	startLog := filepath.Join(directory, "starts.log")
	executable := filepath.Join(directory, "codex")
	script := `#!/bin/sh
echo "$$" >> "$TEST_START_LOG"
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"method":"initialize"'*)
      printf '{"id":%s,"result":{}}\n' "$id"
      ;;
    *'"method":"thread/list"'*)
      case "$line" in
        *'"cursor":"next"'*)
          printf '{"id":%s,"result":{"data":[{"id":"page-2","name":"Second","status":{"type":"idle"}}]}}\n' "$id"
          ;;
        *)
          printf '{"id":%s,"result":{"data":[{"id":"page-1","name":"First","status":{"type":"active","activeFlags":[]}}],"nextCursor":"next"}}\n' "$id"
          ;;
      esac
      ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var mu sync.Mutex
	var events []Event
	var states []string
	controller := NewCodexController(ctx, CodexControllerOptions{
		Environment: map[string]string{
			"HOME": directory, "PATH": directory + ":/bin:/usr/bin", "TEST_START_LOG": startLog,
		},
		QuietPeriod: 80 * time.Millisecond,
		Emit: func(event Event) {
			mu.Lock()
			events = append(events, event)
			mu.Unlock()
		},
		State: func(state, _ string) {
			mu.Lock()
			states = append(states, state)
			mu.Unlock()
		},
	})
	if err := controller.Refresh(ctx); err != nil {
		t.Fatal(err)
	}
	if err := controller.Refresh(ctx); err != nil {
		t.Fatal(err)
	}
	if countFileLines(t, startLog) != 1 {
		t.Fatal("repeated refresh launched more than one child")
	}
	mu.Lock()
	if len(events) != 4 || events[0].SessionID != "page-1" || events[1].SessionID != "page-2" {
		t.Fatalf("paginated events = %#v", events)
	}
	mu.Unlock()
	waitForCondition(t, time.Second, func() bool { return !controller.Running() }, "Codex quiet shutdown")
	if err := controller.Refresh(ctx); err != nil {
		t.Fatal(err)
	}
	if countFileLines(t, startLog) != 2 {
		t.Fatal("refresh after quiet did not restart one child")
	}
	controller.Stop()
	if controller.Running() {
		t.Fatal("controller retained its child after stop")
	}
	mu.Lock()
	if !containsString(states, "idle") || !containsString(states, "stopped") {
		t.Fatalf("controller states = %#v", states)
	}
	mu.Unlock()
}

func TestCodexControllerDegradesUnsupportedMethod(t *testing.T) {
	directory := t.TempDir()
	executable := filepath.Join(directory, "codex")
	script := `#!/bin/sh
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"method":"initialize"'*) printf '{"id":%s,"result":{}}\n' "$id" ;;
    *'"method":"thread/list"'*) printf '{"id":%s,"error":{"code":-32601}}\n' "$id" ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var errorCode string
	controller := NewCodexController(ctx, CodexControllerOptions{
		Environment: map[string]string{"HOME": directory, "PATH": directory + ":/bin:/usr/bin"},
		State: func(_, code string) {
			if code != "" {
				errorCode = code
			}
		},
	})
	if err := controller.Refresh(ctx); err == nil || errorCode != "unsupported_method" {
		t.Fatalf("unsupported refresh err=%v code=%q", err, errorCode)
	}
	if controller.Running() {
		t.Fatal("unsupported app-server remained running")
	}
}

func countFileLines(t *testing.T, path string) int {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return len(strings.Fields(string(data)))
}

func waitForCondition(t *testing.T, timeout time.Duration, condition func() bool, name string) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("%s timed out", name)
}

func containsString(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}
