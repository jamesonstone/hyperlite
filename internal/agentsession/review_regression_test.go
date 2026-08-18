package agentsession

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func TestReviewRegressionUnicodeReasonAndCombinedMessages(t *testing.T) {
	reason := boundedReason(strings.Repeat("é", 80), "")
	if !utf8.ValidString(reason) || len([]rune(reason)) != 64 {
		t.Fatalf("bounded reason is invalid: %q", reason)
	}
	session := Session{Messages: []Message{{Role: "assistant", Text: "old"}}}
	applyEventContent(&session, Event{
		Source: SourceRollout, MessageRole: "user", Message: "single",
		Messages: []Message{{Role: "assistant", Text: "batch"}},
	})
	if len(session.Messages) != 2 || session.Messages[0].Text != "single" || session.Messages[1].Text != "batch" {
		t.Fatalf("combined rollout messages = %#v", session.Messages)
	}
}

func TestReviewRegressionSemanticTimesAndLifecycleClock(t *testing.T) {
	store := NewStore()
	withMonotonic := time.Now()
	plain := withMonotonic.UTC().Round(0)
	event := Event{Provider: "codex", Profile: "codex", SessionID: "same",
		Event: "idle", Phase: PhaseIdle, Source: SourceAppServer, OccurredAt: withMonotonic}
	first, changed := store.Apply(event, withMonotonic)
	event.OccurredAt = plain
	second, duplicateChanged := store.Apply(event, plain)
	if !changed || duplicateChanged || second.Generation != first.Generation {
		t.Fatalf("semantic time duplicate changed generation: %d -> %d", first.Generation, second.Generation)
	}
	if snapshot := store.Snapshot(time.Time{}); snapshot.GeneratedAt.IsZero() {
		t.Fatal("snapshot retained a zero generated_at")
	}
	if snapshot, _ := store.Expire(time.Time{}); snapshot.GeneratedAt.IsZero() {
		t.Fatal("expiry retained a zero generated_at")
	}
}

func TestReviewRegressionHealthUsesObservationTime(t *testing.T) {
	state := NewHealthState([]IntegrationStatus{{ID: "codex", Provider: "codex"}})
	observed := timeForTest()
	historical := observed.Add(-24 * time.Hour)
	health, changed := state.Event(Event{Provider: "codex", Profile: "codex", OccurredAt: historical}, observed)
	if !changed || health.LastEventAt == nil || !health.LastEventAt.Equal(observed) {
		t.Fatalf("health event time = %#v", health.LastEventAt)
	}
	data, err := json.Marshal(health)
	if err != nil || strings.Contains(string(data), historical.Format(time.RFC3339)) {
		t.Fatalf("historical time leaked into health: %s err=%v", data, err)
	}
}

func TestReviewRegressionLargePartialCapacityIsReleased(t *testing.T) {
	cursor := NewRolloutCursor("unused", Event{})
	cursor.partial = make([]byte, 1, maxRolloutRecord)
	_, _ = cursor.consume([]byte("\n"), timeForTest(), rolloutTurnRows)
	if cap(cursor.partial) > rolloutChunkBytes {
		t.Fatalf("partial capacity remained pinned: %d", cap(cursor.partial))
	}
}
