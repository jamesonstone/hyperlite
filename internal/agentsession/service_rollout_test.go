package agentsession

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRolloutCursorInitialAdvanceIsBounded(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rollout.jsonl")
	data := []byte(`{"timestamp":"2026-08-17T12:00:00Z","type":"session_meta","payload":{"id":"thread-1"}}` + "\n")
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	cursor := NewRolloutCursor(path, Event{Provider: "codex", Profile: "codex", SessionID: "thread-1", Title: "Stored task"})
	event, changed, more, readBytes, err := cursor.Advance(time.Now().UTC(), rolloutTurnBytes, rolloutTurnRows)
	if err != nil || !changed || more || readBytes > rolloutTurnBytes {
		t.Fatalf("initial cursor advance = %#v changed=%v more=%v bytes=%d err=%v", event, changed, more, readBytes, err)
	}
	if event.SessionID != "thread-1" || event.Title != "Stored task" {
		t.Fatalf("initial rollout event = %#v", event)
	}
}

func TestRolloutWatchRejectsMismatchedIdentity(t *testing.T) {
	if event, ok := reconcileRolloutSeed(
		Event{SessionID: "other-thread"},
		Event{SessionID: "expected-thread"},
	); ok {
		t.Fatalf("mismatched rollout accepted: %#v", event)
	}
}

func TestServiceProjectsNotLoadedThreadFromRolloutOnly(t *testing.T) {
	home := t.TempDir()
	sessions := filepath.Join(home, ".codex", "sessions")
	if err := os.MkdirAll(sessions, 0o700); err != nil {
		t.Fatal(err)
	}
	rollout := filepath.Join(sessions, "rollout.jsonl")
	timestamp := time.Now().UTC().Format(time.RFC3339Nano)
	data := []byte(
		fmt.Sprintf(`{"timestamp":%q,"type":"session_meta","payload":{"id":"thread-1","cwd":"/tmp/project"}}`, timestamp) + "\n" +
			fmt.Sprintf(`{"timestamp":%q,"type":"event_msg","payload":{"type":"task_started"}}`, timestamp) + "\n",
	)
	if err := os.WriteFile(rollout, data, 0o600); err != nil {
		t.Fatal(err)
	}
	executable := filepath.Join(home, "codex")
	script := `#!/bin/sh
IFS= read -r initialize
printf '%s\n' '{"id":1,"result":{}}'
IFS= read -r initialized
IFS= read -r list
printf '{"id":2,"result":{"data":[{"id":"thread-1","name":"Stored task","cwd":"/tmp/project","path":"%s","status":{"type":"notLoaded"}}]}}\n' "$TEST_ROLLOUT_PATH"
IFS= read -r keep_open
`
	if err := os.WriteFile(executable, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	inputReader, inputWriter := io.Pipe()
	outputReader, outputWriter := io.Pipe()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	runtimeDir := filepath.Join("/tmp", fmt.Sprintf("hl-agent-rollout-%d-%d", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.RemoveAll(runtimeDir) })
	done := make(chan error, 1)
	go func() {
		defer func() { _ = outputWriter.Close() }()
		done <- RunService(ctx, inputReader, outputWriter, io.Discard, ServiceOptions{
			SocketPath: filepath.Join(runtimeDir, "agent.sock"), Home: home,
			Environment: map[string]string{
				"HOME": home, "PATH": home + ":/bin:/usr/bin", "TEST_ROLLOUT_PATH": rollout,
				"XDG_STATE_HOME": filepath.Join(home, "state"),
			},
		})
	}()
	t.Cleanup(func() {
		cancel()
		_ = inputWriter.Close()
		_ = outputReader.Close()
		_ = outputWriter.Close()
		<-done
	})
	decoder := json.NewDecoder(outputReader)
	var initial Snapshot
	if err := decoder.Decode(&initial); err != nil || len(initial.Sessions) != 0 {
		t.Fatalf("initial snapshot = %#v %v", initial, err)
	}
	var discovered Snapshot
	if err := decodeAgentSnapshot(decoder, &discovered); err != nil {
		t.Fatal(err)
	}
	if len(discovered.Sessions) != 1 || discovered.Sessions[0].ID != "codex:thread-1" ||
		discovered.Sessions[0].Source != SourceRollout || discovered.Sessions[0].Phase != PhaseProcessing {
		t.Fatalf("discovered snapshot = %#v", discovered)
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
