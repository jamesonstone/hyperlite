package agentsession

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRolloutRegistryAdmissionEvictionAndRelease(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var utilization []int
	registry := NewRolloutRegistry(ctx, nil, func(used int) { utilization = append(utilization, used) })
	base := timeForTest()
	for index := 0; index < maxCodexRolloutWatches; index++ {
		phase := PhaseIdle
		if index == 0 {
			phase = PhaseWaitingInput
		}
		path := fmt.Sprintf("/tmp/rollout-%02d.jsonl", index)
		_, added := registry.Admit(path, Event{Provider: "codex", SessionID: fmt.Sprintf("s-%02d", index),
			Phase: phase, OccurredAt: base.Add(time.Duration(index) * time.Second)}, false, base)
		if !added {
			t.Fatalf("admission %d failed", index)
		}
	}
	evicted, added := registry.Admit("/tmp/new.jsonl", Event{Provider: "codex", SessionID: "new",
		Phase: PhaseProcessing, OccurredAt: base.Add(time.Hour)}, false, base)
	if !added || evicted != "/tmp/rollout-01.jsonl" || registry.Len() != maxCodexRolloutWatches {
		t.Fatalf("eviction = %q added=%v count=%d", evicted, added, registry.Len())
	}
	if _, exists := registry.Entry("/tmp/rollout-00.jsonl"); !exists {
		t.Fatal("unresolved-attention watcher was evicted")
	}
	if removed := registry.ReleaseIdentity("codex:new"); removed != 1 || registry.Len() != 31 {
		t.Fatalf("release removed=%d count=%d", removed, registry.Len())
	}
	if len(utilization) == 0 || utilization[len(utilization)-1] != 31 {
		t.Fatalf("utilization updates = %#v", utilization)
	}
}

func TestRolloutRegistryNeverEvictsAttention(t *testing.T) {
	registry := NewRolloutRegistry(context.Background(), nil, nil)
	for index := 0; index < maxCodexRolloutWatches; index++ {
		registry.Admit(fmt.Sprintf("/tmp/a-%d", index), Event{Provider: "codex",
			SessionID: fmt.Sprint(index), Phase: PhaseWaitingApproval}, false, timeForTest())
	}
	if evicted, added := registry.Admit("/tmp/rejected", Event{Provider: "codex",
		SessionID: "rejected", Phase: PhaseProcessing}, false, timeForTest()); added || evicted != "" {
		t.Fatalf("attention registry admitted by eviction: evicted=%q added=%v", evicted, added)
	}
}

func TestRolloutRegistryHintDoesNotDowngradeActiveWatcher(t *testing.T) {
	registry := NewRolloutRegistry(context.Background(), nil, nil)
	now := timeForTest()
	path := "/tmp/active"
	registry.Admit(path, Event{Provider: "codex", SessionID: "active",
		Phase: PhaseProcessing, OccurredAt: now}, false, now)
	registry.Update(path, Event{Provider: "codex", SessionID: "active",
		Phase: PhaseProcessing, OccurredAt: now.Add(time.Minute)})
	registry.Admit(path, Event{Provider: "codex", SessionID: "active",
		OccurredAt: now.Add(-time.Hour)}, false, now)
	entry, ok := registry.Entry(path)
	if !ok || entry.priority != 3 || !entry.updatedAt.Equal(now.Add(time.Minute)) {
		t.Fatalf("active watcher was downgraded: %#v", entry)
	}
}

func TestRolloutRegistryRejectsOlderEqualPriorityAdmission(t *testing.T) {
	registry := NewRolloutRegistry(context.Background(), nil, nil)
	now := timeForTest()
	for index := 0; index < maxCodexRolloutWatches; index++ {
		registry.Admit(fmt.Sprintf("/tmp/fresh-%d", index), Event{Provider: "codex",
			SessionID: fmt.Sprint(index), Phase: PhaseIdle, OccurredAt: now.Add(time.Duration(index) * time.Second)}, false, now)
	}
	if evicted, added := registry.Admit("/tmp/old", Event{Provider: "codex",
		SessionID: "old", Phase: PhaseIdle, OccurredAt: now.Add(-time.Hour)}, false, now); added || evicted != "" {
		t.Fatalf("older hint displaced a fresher watcher: evicted=%q added=%v", evicted, added)
	}
}

func TestCodexDateDirectoryDiscoveryIsCurrentAndBounded(t *testing.T) {
	home := t.TempDir()
	now := time.Date(2026, 8, 18, 23, 59, 0, 0, time.Local)
	directory := codexDateDirectory(home, now)
	if want := filepath.Join(home, ".codex", "sessions", "2026", "08", "18"); directory != want {
		t.Fatalf("date directory = %q want %q", directory, want)
	}
	if err := os.MkdirAll(directory, 0o700); err != nil {
		t.Fatal(err)
	}
	for index := 0; index < 40; index++ {
		path := filepath.Join(directory, fmt.Sprintf("rollout-%02d.jsonl", index))
		writeRollout(t, path, rolloutRow("session_meta", fmt.Sprintf(`{"id":"%d"}`, index)))
		updated := now.Add(time.Duration(index) * time.Second)
		if err := os.Chtimes(path, updated, updated); err != nil {
			t.Fatal(err)
		}
	}
	oldDirectory := filepath.Join(home, ".codex", "sessions", "2026", "08", "17")
	if err := os.MkdirAll(oldDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	writeRollout(t, filepath.Join(oldDirectory, "old.jsonl"), rolloutRow("session_meta", `{"id":"old"}`))
	candidates := discoverCodexRollouts(home, now)
	if len(candidates) != maxCodexRolloutWatches {
		t.Fatalf("candidate count = %d", len(candidates))
	}
	if filepath.Base(candidates[0].path) != "rollout-39.jsonl" {
		t.Fatalf("freshest candidate = %q", candidates[0].path)
	}
	if !nextLocalDay(now).Equal(time.Date(2026, 8, 19, 0, 0, 0, 0, time.Local)) {
		t.Fatalf("next day = %v", nextLocalDay(now))
	}
}
