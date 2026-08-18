package agentsession

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRolloutCursorReadsOnlyAppendedRecords(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rollout.jsonl")
	writeRollout(t, path,
		rolloutRow("session_meta", `{"id":"thread-1","cwd":"/tmp/project"}`),
		rolloutRow("event_msg", `{"type":"task_started"}`))
	cursor := NewRolloutCursor(path, Event{Provider: "codex", Profile: "codex", SessionID: "thread-1"})
	event, changed, more, readBytes, err := cursor.Advance(timeForTest(), rolloutTurnBytes, rolloutTurnRows)
	if err != nil || !changed || more || event.Phase != PhaseProcessing || readBytes <= 0 {
		t.Fatalf("initial advance = %#v changed=%v more=%v bytes=%d err=%v", event, changed, more, readBytes, err)
	}
	initialOffset := cursor.offset
	appended := rolloutRow("event_msg", `{"type":"task_complete"}`) + "\n"
	appendRaw(t, path, appended)
	event, changed, more, readBytes, err = cursor.Advance(timeForTest().Add(time.Second), rolloutTurnBytes, rolloutTurnRows)
	if err != nil || !changed || more || event.Phase != PhaseCompleted {
		t.Fatalf("append advance = %#v changed=%v more=%v err=%v", event, changed, more, err)
	}
	if cursor.offset-initialOffset != int64(len(appended)) {
		t.Fatalf("cursor offset did not advance by appended bytes: previous=%d current=%d read=%d", initialOffset, cursor.offset, readBytes)
	}
}

func TestRolloutCursorRetainsPartialAndDiscardsOversizedRecord(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rollout.jsonl")
	partial := rolloutRow("session_meta", `{"id":"thread-1"}`)
	if err := os.WriteFile(path, []byte(partial), 0o600); err != nil {
		t.Fatal(err)
	}
	cursor := NewRolloutCursor(path, Event{Provider: "codex", Profile: "codex", SessionID: "thread-1"})
	if event, changed, _, _, err := cursor.Advance(timeForTest(), rolloutTurnBytes, rolloutTurnRows); err != nil || changed || event.SessionID != "thread-1" {
		t.Fatalf("unterminated record was projected: %#v changed=%v err=%v", event, changed, err)
	}
	appendRaw(t, path, "\n"+strings.Repeat("x", maxRolloutRecord+1)+"\n"+
		rolloutRow("event_msg", `{"type":"task_started"}`)+"\n")
	var event Event
	for turns := 0; turns < 8; turns++ {
		var more bool
		var err error
		event, _, more, _, err = cursor.Advance(timeForTest(), rolloutTurnBytes, rolloutTurnRows)
		if err != nil {
			t.Fatal(err)
		}
		if !more {
			break
		}
	}
	if event.SessionID != "thread-1" || event.Phase != PhaseProcessing || len(cursor.partial) > maxRolloutRecord {
		t.Fatalf("oversized recovery = %#v partial=%d", event, len(cursor.partial))
	}
}

func TestRolloutCursorRecoversTruncationAndReplacement(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rollout.jsonl")
	seed := Event{Provider: "codex", Profile: "codex", SessionID: "thread-1"}
	writeRollout(t, path, rolloutRow("session_meta", `{"id":"thread-1"}`),
		rolloutRow("event_msg", `{"type":"task_started"}`))
	cursor := NewRolloutCursor(path, seed)
	if event, _, _, _, err := cursor.Advance(timeForTest(), rolloutTurnBytes, rolloutTurnRows); err != nil || event.Phase != PhaseProcessing {
		t.Fatalf("initial projection: %#v %v", event, err)
	}
	writeRollout(t, path, rolloutRow("session_meta", `{"id":"thread-1"}`),
		rolloutRow("event_msg", `{"type":"task_complete"}`))
	if event, changed, _, _, err := cursor.Advance(timeForTest(), rolloutTurnBytes, rolloutTurnRows); err != nil || !changed || event.Phase != PhaseCompleted {
		t.Fatalf("truncation projection: %#v changed=%v err=%v", event, changed, err)
	}
	replacement := filepath.Join(filepath.Dir(path), "replacement.jsonl")
	writeRollout(t, replacement, rolloutRow("session_meta", `{"id":"thread-1"}`),
		rolloutRow("event_msg", `{"type":"task_started"}`))
	if err := os.Rename(replacement, path); err != nil {
		t.Fatal(err)
	}
	if event, changed, _, _, err := cursor.Advance(timeForTest(), rolloutTurnBytes, rolloutTurnRows); err != nil || !changed || event.Phase != PhaseProcessing {
		t.Fatalf("replacement projection: %#v changed=%v err=%v", event, changed, err)
	}
	writeRollout(t, replacement, rolloutRow("session_meta", `{"id":"other"}`))
	if err := os.Rename(replacement, path); err != nil {
		t.Fatal(err)
	}
	if _, _, _, _, err := cursor.Advance(timeForTest(), rolloutTurnBytes, rolloutTurnRows); !errors.Is(err, ErrRolloutIdentityMismatch) {
		t.Fatalf("mismatched replacement error = %v", err)
	}
}

func TestRolloutCursorHonorsPerTurnBudgets(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rollout.jsonl")
	lines := []string{rolloutRow("session_meta", `{"id":"thread-1"}`)}
	for index := 0; index < 1_000; index++ {
		lines = append(lines, rolloutRow("event_msg", fmt.Sprintf(`{"type":"user_message","message":"%04d-%s"}`, index, strings.Repeat("x", 600))))
	}
	writeRollout(t, path, lines...)
	cursor := NewRolloutCursor(path, Event{Provider: "codex", Profile: "codex", SessionID: "thread-1"})
	_, _, more, readBytes, err := cursor.Advance(timeForTest(), rolloutTurnBytes, rolloutTurnRows)
	if err != nil || !more || readBytes > rolloutTurnBytes {
		t.Fatalf("budget advance more=%v bytes=%d err=%v", more, readBytes, err)
	}
}

func TestRolloutCursorPrefixDoesNotRetainSkippedToolState(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rollout.jsonl")
	prefix := []string{
		rolloutRow("session_meta", `{"id":"thread-1"}`),
		rolloutRow("response_item", `{"type":"custom_tool_call","call_id":"old","name":"shell"}`),
	}
	padding := strings.Repeat("x", maxRolloutTail+1024) + "\n"
	tail := rolloutRow("event_msg", `{"type":"task_complete"}`) + "\n"
	if err := os.WriteFile(path, []byte(strings.Join(prefix, "\n")+"\n"+padding+tail), 0o600); err != nil {
		t.Fatal(err)
	}
	cursor := NewRolloutCursor(path, Event{Provider: "codex", Profile: "codex", SessionID: "thread-1"})
	var event Event
	for turns := 0; turns < 20; turns++ {
		var more bool
		var err error
		event, _, more, _, err = cursor.Advance(timeForTest(), rolloutTurnBytes, rolloutTurnRows)
		if err != nil {
			t.Fatal(err)
		}
		if !more {
			break
		}
	}
	if event.Phase != PhaseCompleted || event.ActiveTool {
		t.Fatalf("skipped prefix tool polluted tail projection: %#v", event)
	}
}

func rolloutRow(kind, payload string) string {
	return fmt.Sprintf(`{"timestamp":"2026-08-18T12:00:00Z","type":%q,"payload":%s}`, kind, payload)
}

func writeRollout(t *testing.T, path string, lines ...string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
}

func appendRollout(t *testing.T, path string, lines ...string) {
	t.Helper()
	appendRaw(t, path, strings.Join(lines, "\n")+"\n")
}

func appendRaw(t *testing.T, path, value string) {
	t.Helper()
	file, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = file.Close() }()
	if _, err := file.Write([]byte(value)); err != nil {
		t.Fatal(err)
	}
}

func TestRolloutCursorDoesNotRetainRawRecords(t *testing.T) {
	cursor := NewRolloutCursor("unused", Event{})
	cursor.partial = bytes.Repeat([]byte("x"), maxRolloutRecord)
	_, _ = cursor.consume([]byte("x\n"), timeForTest(), rolloutTurnRows)
	if len(cursor.partial) != 0 || cursor.discarding {
		t.Fatalf("oversized raw state retained: partial=%d discarding=%v", len(cursor.partial), cursor.discarding)
	}
}
