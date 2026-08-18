package agentsession

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestReadRolloutTailNeverReadsWholeOversizedFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rollout.jsonl")
	prefix := append([]byte("origin-only-secret\n"), bytes.Repeat([]byte("filler\n"), 300_000)...)
	tail := []byte(`{"timestamp":"2026-08-17T12:00:00Z","type":"event_msg","payload":{"type":"task_complete"}}` + "\n")
	if err := os.WriteFile(path, append(prefix, tail...), 0o600); err != nil {
		t.Fatal(err)
	}
	data, err := ReadRolloutTail(path, 128*1024)
	if err != nil {
		t.Fatal(err)
	}
	if len(data) > 128*1024 || bytes.Contains(data, []byte("origin-only-secret")) {
		t.Fatalf("tail read crossed bound: bytes=%d", len(data))
	}
	if !bytes.Contains(data, []byte("task_complete")) {
		t.Fatal("latest row missing")
	}
}

func TestParseCodexRolloutTailFiltersReasoningAndBoundsHistory(t *testing.T) {
	var lines []string
	lines = append(lines, `{"timestamp":"2026-08-17T12:00:00Z","type":"session_meta","payload":{"id":"thread-1","cwd":"/tmp/project","title":"Safe task"}}`)
	for index := 0; index < 8; index++ {
		lines = append(lines, fmt.Sprintf(`{"timestamp":"2026-08-17T12:00:%02dZ","type":"event_msg","payload":{"type":"user_message","message":"user %d"}}`, index+1, index))
	}
	lines = append(lines,
		`{"timestamp":"2026-08-17T12:01:00Z","type":"event_msg","payload":{"type":"agent_message","phase":"commentary","message":"internal reasoning"}}`,
		`{"timestamp":"2026-08-17T12:01:01Z","type":"event_msg","payload":{"type":"agent_message","phase":"final","message":"final result"}}`,
		`{"timestamp":"2026-08-17T12:01:02Z","type":"event_msg","payload":{"type":"task_complete"}}`)
	event, err := ParseCodexRolloutTail([]byte(strings.Join(lines, "\n")), "fallback", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if event.SessionID != "thread-1" || event.Phase != PhaseCompleted || event.LatestResult != "final result" {
		t.Fatalf("unexpected event: %#v", event)
	}
	if len(event.Messages) != maxMessages {
		t.Fatalf("message count = %d", len(event.Messages))
	}
	for _, message := range event.Messages {
		if strings.Contains(message.Text, "reasoning") {
			t.Fatalf("reasoning leaked: %#v", event.Messages)
		}
	}
}

func TestParseCodexRolloutQuestionIsOpenInClientOnly(t *testing.T) {
	data := []byte(`{"timestamp":"2026-08-17T12:00:00Z","type":"response_item","payload":{"type":"function_call","call_id":"call-1","name":"request_user_input","arguments":"{}"}}`)
	event, err := ParseCodexRolloutTail(data, "thread-1", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if event.Phase != PhaseWaitingInput || event.ExpectsResponse || event.CompleteContext {
		t.Fatalf("rollout question became actionable: %#v", event)
	}
}

func TestParseCodexResolvedRolloutQuestionReturnsToProcessing(t *testing.T) {
	data := []byte(strings.Join([]string{
		`{"timestamp":"2026-08-18T12:00:00Z","type":"response_item","payload":{"type":"function_call","call_id":"call-1","name":"request_user_input","arguments":"{}"}}`,
		`{"timestamp":"2026-08-18T12:00:01Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call-1","output":"answered"}}`,
	}, "\n"))
	event, err := ParseCodexRolloutTail(data, "thread-1", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if event.Phase != PhaseProcessing || event.ActionKind != "" || event.ActionTitle != "" {
		t.Fatalf("resolved question retained attention: %#v", event)
	}
}

func TestCodexRolloutPathIsConfinedAndWatchIsEventDriven(t *testing.T) {
	home := t.TempDir()
	directory := filepath.Join(home, ".codex", "sessions")
	if err := os.MkdirAll(directory, 0o700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "rollout.jsonl")
	if err := os.WriteFile(path, []byte("{}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	resolved, err := SafeCodexRolloutPath(path, home)
	expectedPath, resolveErr := filepath.EvalSymlinks(path)
	if resolveErr != nil {
		t.Fatal(resolveErr)
	}
	if err != nil || resolved != expectedPath {
		t.Fatalf("safe path: %q %v", resolved, err)
	}
	outside := filepath.Join(t.TempDir(), "outside.jsonl")
	if err := os.WriteFile(outside, []byte("{}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := SafeCodexRolloutPath(outside, home); err == nil {
		t.Fatal("outside rollout accepted")
	}
	symlinkedDirectory := filepath.Join(directory, "linked")
	if err := os.Symlink(filepath.Dir(outside), symlinkedDirectory); err != nil {
		t.Fatal(err)
	}
	if _, err := SafeCodexRolloutPath(filepath.Join(symlinkedDirectory, filepath.Base(outside)), home); err == nil {
		t.Fatal("rollout through escaping directory symlink was accepted")
	}
	if runtime.GOOS != "darwin" {
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	changed := make(chan struct{}, 1)
	done := make(chan error, 1)
	go func() {
		done <- WatchRollout(ctx, path, func() {
			select {
			case changed <- struct{}{}:
			default:
			}
		})
	}()
	appendLine := func() {
		file, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := file.WriteString("{}\n"); err != nil {
			_ = file.Close()
			t.Fatal(err)
		}
		if err := file.Close(); err != nil {
			t.Fatal(err)
		}
	}
	deadline := time.NewTimer(2 * time.Second)
	defer deadline.Stop()
	retry := time.NewTicker(20 * time.Millisecond)
	defer retry.Stop()
	for observed := false; !observed; {
		appendLine()
		select {
		case <-changed:
			observed = true
		case <-retry.C:
		case <-deadline.C:
			t.Fatal("rollout watcher did not observe append")
		}
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("rollout watcher did not stop")
	}
}
