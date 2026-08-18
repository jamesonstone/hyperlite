package agentsession

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"
)

func TestStoreBoundsAndResolvesIndependentActionQueue(t *testing.T) {
	store := NewStore()
	base := timeForTest()
	for index := 0; index < maxPendingActions+1; index++ {
		store.Apply(Event{
			Provider: "claude", Profile: "claude-code", SessionID: "queue",
			Event: "PermissionRequest", Phase: PhaseWaitingApproval, Source: SourceHook,
			OccurredAt: base.Add(time.Duration(index) * time.Second),
			RequestID:  fmt.Sprintf("request-%d", index), ActionKind: "approval",
			ActionContext: "git status", CompleteContext: true, ExpectsResponse: true,
		}, base.Add(time.Duration(index)*time.Second))
	}
	session := store.Snapshot(base.Add(time.Minute)).Sessions[0]
	if len(session.Actions) != maxPendingActions || session.Actions[0].RequestID != "request-0" {
		t.Fatalf("bounded action queue = %#v", session.Actions)
	}
	firstRevision := session.Actions[0].Revision
	store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "queue",
		Event: "PostToolUse", Phase: PhaseProcessing, Source: SourceHook,
		OccurredAt: base.Add(20 * time.Second)}, base.Add(20*time.Second))
	session = store.Snapshot(base.Add(time.Minute)).Sessions[0]
	if session.Actions[0].Revision != firstRevision {
		t.Fatalf("unrelated event changed action revision: %d -> %d", firstRevision, session.Actions[0].Revision)
	}
	request := ActionRequest{Schema: ActionSchema, Provider: "claude", SessionID: session.ID,
		RequestID: "request-3", Revision: session.Actions[3].Revision, Action: "deny"}
	if _, err := store.ValidateAction(request); err != nil {
		t.Fatal(err)
	}
	resolved := store.ResolveAction(request, base.Add(time.Minute))
	if len(resolved.Sessions[0].Actions) != maxPendingActions-1 {
		t.Fatalf("independent resolution removed wrong requests: %#v", resolved.Sessions[0].Actions)
	}
	if _, ok := actionByRequest(resolved.Sessions[0].Actions, "request-3"); ok {
		t.Fatal("resolved request remained queued")
	}
}

func TestStoreAcceptsOneReleaseV1ActionCompatibility(t *testing.T) {
	store := NewStore()
	now := timeForTest()
	store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "legacy",
		Event: "PermissionRequest", Source: SourceHook, OccurredAt: now,
		RequestID: "request", ActionKind: "approval", ActionContext: "pwd",
		CompleteContext: true, ExpectsResponse: true}, now)
	snapshot, _ := store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "legacy",
		Event: "PostToolUse", Phase: PhaseProcessing, Source: SourceHook,
		OccurredAt: now.Add(time.Second)}, now.Add(time.Second))
	request := ActionRequest{Schema: ActionSchemaV1, SessionID: "claude:legacy",
		RequestID: "request", Revision: snapshot.Sessions[0].Revision, Action: "deny"}
	if _, err := store.ValidateAction(request); err != nil {
		t.Fatalf("v1 action compatibility rejected: %v", err)
	}
}

func TestStoreBoundsSessionsAndTransitionHistory(t *testing.T) {
	store := NewStore()
	base := timeForTest()
	store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "attention",
		Event: "PermissionRequest", Source: SourceHook, OccurredAt: base,
		RequestID: "request", ActionKind: "approval", ActionContext: "pwd",
		CompleteContext: true, ExpectsResponse: true}, base)
	for index := 0; index < maxSessions+10; index++ {
		now := base.Add(time.Duration(index+1) * time.Second)
		store.Apply(Event{Provider: "codex", Profile: "codex", SessionID: fmt.Sprintf("s-%03d", index),
			Event: "active", Phase: PhaseProcessing, Source: SourceAppServer, OccurredAt: now}, now)
	}
	snapshot := store.Snapshot(base.Add(time.Hour))
	if len(snapshot.Sessions) != maxSessions {
		t.Fatalf("session bound = %d", len(snapshot.Sessions))
	}
	if !store.Has("claude:attention") {
		t.Fatal("session admission evicted unresolved attention")
	}
	for index := 0; index < maxPhaseTransitions+20; index++ {
		phase := PhaseIdle
		if index%2 == 0 {
			phase = PhaseProcessing
		}
		now := base.Add(time.Duration(index+1) * time.Minute)
		store.Apply(Event{Provider: "codex", Profile: "codex", SessionID: "transition",
			Event: "status", Phase: phase, Source: SourceAppServer, OccurredAt: now,
			ReasonCode: "status_changed"}, now)
	}
	transitions := store.Transitions()
	if len(transitions) != maxPhaseTransitions {
		t.Fatalf("transition bound = %d", len(transitions))
	}
	data, err := json.Marshal(transitions)
	if err != nil || strings.Contains(string(data), "message") || strings.Contains(string(data), "argument") {
		t.Fatalf("transition history retained content: %s err=%v", data, err)
	}
}

func TestSyntheticSelfTestCannotBypassAttentionSaturatedStore(t *testing.T) {
	store := NewStore()
	now := timeForTest()
	for index := 0; index < maxSessions; index++ {
		store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: fmt.Sprint(index),
			Event: "PermissionRequest", Source: SourceHook, OccurredAt: now.Add(time.Duration(index) * time.Second),
			RequestID: fmt.Sprintf("request-%d", index), ActionKind: "approval",
			ActionContext: "pwd", CompleteContext: true, ExpectsResponse: true,
		}, now.Add(time.Duration(index)*time.Second))
	}
	_, changed := store.Apply(Event{Provider: "claude", Profile: "claude-code",
		SessionID: "hyperlite-self-test", Event: "integration_self_test",
		Source: SourceHook, OccurredAt: now.Add(time.Hour), Synthetic: true}, now.Add(time.Hour))
	if changed || store.Has("claude:hyperlite-self-test") {
		t.Fatal("synthetic self-test bypassed the bounded attention store")
	}
}

func TestStoreSuppressesSemanticDuplicateGeneration(t *testing.T) {
	store := NewStore()
	now := timeForTest()
	event := Event{Provider: "codex", Profile: "codex", SessionID: "same",
		Event: "idle", Phase: PhaseIdle, Source: SourceAppServer, OccurredAt: now}
	first, changed := store.Apply(event, now)
	if !changed {
		t.Fatal("initial event was not accepted")
	}
	second, changed := store.Apply(event, now)
	if changed || second.Generation != first.Generation {
		t.Fatalf("duplicate advanced generation: %d -> %d changed=%v", first.Generation, second.Generation, changed)
	}
}

func TestVisibilityGateFiltersAuxiliaryAndDelaysBlank(t *testing.T) {
	gate := NewVisibilityGate()
	now := timeForTest()
	auxiliary := Event{Provider: "codex", SessionID: "aux", Source: SourceAppServer,
		AuxiliaryKind: "subAgentCompact", Phase: PhaseProcessing}
	if _, publish, filtered := gate.Offer(auxiliary, false, now); publish || !filtered {
		t.Fatal("explicit auxiliary row was not filtered")
	}
	blank := Event{Provider: "codex", SessionID: "blank", Source: SourceAppServer, Phase: PhaseIdle}
	if _, publish, filtered := gate.Offer(blank, false, now); publish || filtered {
		t.Fatal("blank placeholder did not enter grace")
	}
	if events, filtered := gate.Due(now.Add(time.Second)); len(events) != 0 || filtered != 0 {
		t.Fatalf("blank released before grace: %#v filtered=%d", events, filtered)
	}
	material := blank
	material.HasPrompt = true
	material.Phase = PhaseProcessing
	if event, publish, filtered := gate.Offer(material, false, now.Add(time.Second)); !publish || filtered || !event.HasPrompt {
		t.Fatalf("material evidence did not cancel grace: %#v publish=%v filtered=%v", event, publish, filtered)
	}
	gate.Offer(blank, false, now)
	if events, filtered := gate.Due(now.Add(blankSessionGrace)); len(events) != 0 || filtered != 1 {
		t.Fatalf("corroborated blank was not filtered: %#v filtered=%d", events, filtered)
	}
	hookBlank := Event{Provider: "claude", SessionID: "hook-blank", Source: SourceHook, Phase: PhaseIdle}
	gate.Offer(hookBlank, false, now)
	events, filtered := gate.Due(now.Add(blankSessionGrace))
	if len(events) != 1 || filtered != 0 {
		t.Fatalf("non-corroborated hook blank did not release: %#v filtered=%d", events, filtered)
	}
	if _, publish, _ := gate.Offer(events[0], false, now.Add(blankSessionGrace)); !publish {
		t.Fatal("released blank row re-entered grace")
	}
}

func TestSnapshotSchedulerCoalescesOrdinaryAndEmitsUrgent(t *testing.T) {
	now := timeForTest()
	scheduler := &SnapshotScheduler{}
	initial := Snapshot{Schema: SnapshotSchema, Generation: 1}
	if _, emit := scheduler.Submit(initial, false, now); !emit {
		t.Fatal("initial snapshot was not emitted")
	}
	ordinary := Snapshot{Schema: SnapshotSchema, Generation: 2}
	if _, emit := scheduler.Submit(ordinary, false, now.Add(10*time.Millisecond)); emit {
		t.Fatal("ordinary burst was not coalesced")
	}
	urgent := Snapshot{Schema: SnapshotSchema, Generation: 3}
	if value, emit := scheduler.Submit(urgent, true, now.Add(20*time.Millisecond)); !emit || value.Generation != 3 {
		t.Fatalf("urgent snapshot was delayed: %#v emit=%v", value, emit)
	}
	if _, pending := scheduler.NextDeadline(); pending {
		t.Fatal("urgent snapshot did not clear stale ordinary projection")
	}
}

func TestHealthRecordIsMetadataOnlyAndBounded(t *testing.T) {
	state := NewHealthState([]IntegrationStatus{{ID: "codex", Provider: "codex"}})
	state.Watchers(999)
	state.Filtered("codex", 2)
	state.Rejected("codex", strings.Repeat("x", 100))
	value := state.All()[0]
	if value.WatchersUsed != maxCodexRolloutWatches || len(value.ErrorCode) > 64 {
		t.Fatalf("health bounds = %#v", value)
	}
	data, err := json.Marshal(value)
	if err != nil || strings.Contains(string(data), "/tmp/") || strings.Contains(string(data), "prompt") {
		t.Fatalf("health leaked content: %s err=%v", data, err)
	}
}
