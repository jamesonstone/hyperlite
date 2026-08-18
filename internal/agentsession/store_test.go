package agentsession

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestStorePreservesHigherAuthorityAndValidatesExactAction(t *testing.T) {
	now := time.Date(2026, 8, 17, 12, 0, 0, 0, time.UTC)
	store := NewStore()
	snapshot, changed := store.Apply(Event{
		Provider: "claude", Profile: "claude-code", SessionID: "session-1",
		Event: "PermissionRequest", Source: SourceHook, OccurredAt: now,
		WorkspacePath: "/tmp/project", RequestID: "request-1",
		ActionKind: "approval", ActionTitle: "Allow Bash?",
		ActionContext: "git status --short", CompleteContext: true,
		ExpectsResponse: true,
	}, now)
	if !changed || len(snapshot.Sessions) != 1 {
		t.Fatalf("unexpected snapshot: %#v", snapshot)
	}
	session := snapshot.Sessions[0]
	if session.ID != "claude:session-1" || session.Action == nil || !session.Action.CanAllowOnce {
		t.Fatalf("unexpected session: %#v", session)
	}
	stale := Event{
		Provider: "claude", Profile: "claude-code", SessionID: "session-1",
		Event: "idle", Phase: PhaseIdle, Source: SourceRollout,
		OccurredAt: now.Add(-time.Second),
	}
	if _, accepted := store.Apply(stale, now); accepted {
		t.Fatal("stale lower-authority event was accepted")
	}
	laterLower := stale
	laterLower.OccurredAt = now.Add(time.Minute)
	if _, accepted := store.Apply(laterLower, now.Add(time.Minute)); accepted {
		t.Fatal("lower-authority event replaced a live exact action")
	}
	request := ActionRequest{Schema: ActionSchema, SessionID: session.ID,
		RequestID: "request-1", Revision: session.Revision, Action: "allow_once"}
	if _, err := store.ValidateAction(request); err != nil {
		t.Fatalf("validate exact action: %v", err)
	}
	request.Revision++
	if _, err := store.ValidateAction(request); !errors.Is(err, ErrStaleAction) {
		t.Fatalf("expected stale action, got %v", err)
	}
}

func TestStoreBoundsMessagesAndExpiry(t *testing.T) {
	now := time.Date(2026, 8, 17, 12, 0, 0, 0, time.UTC)
	store := NewStore()
	for index := 0; index < 8; index++ {
		store.Apply(Event{
			Provider: "codex", Profile: "codex", SessionID: "thread-1",
			Event: "agentMessage", Phase: PhaseProcessing, Source: SourceHook,
			OccurredAt:  now.Add(time.Duration(index) * time.Second),
			MessageRole: "assistant", Message: strings.Repeat("x", maxMessageRunes+50),
		}, now.Add(time.Duration(index)*time.Second))
	}
	snapshot := store.Snapshot(now.Add(8 * time.Second))
	if got := len(snapshot.Sessions[0].Messages); got != maxMessages {
		t.Fatalf("message count = %d", got)
	}
	if got := []rune(snapshot.Sessions[0].Messages[0].Text); len(got) != maxMessageRunes {
		t.Fatalf("bounded runes = %d", len(got))
	}
	store.Apply(Event{Provider: "codex", Profile: "codex", SessionID: "thread-1",
		Event: "completed", Phase: PhaseCompleted, Source: SourceHook,
		OccurredAt: now.Add(9 * time.Second)}, now.Add(9*time.Second))
	if expired, changed := store.Expire(now.Add(10*time.Minute + 10*time.Second)); !changed || len(expired.Sessions) != 0 {
		t.Fatalf("completed session did not expire: %#v", expired)
	}
}

func TestAttentionDoesNotAgeExpire(t *testing.T) {
	now := time.Date(2026, 8, 17, 12, 0, 0, 0, time.UTC)
	store := NewStore()
	store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "one",
		Event: "PermissionRequest", Source: SourceHook, OccurredAt: now,
		RequestID: "request", ActionKind: "approval", ActionContext: "ls",
		CompleteContext: true, ExpectsResponse: true}, now)
	snapshot, changed := store.Expire(now.Add(72 * time.Hour))
	if changed || len(snapshot.Sessions) != 1 {
		t.Fatalf("attention session expired: %#v", snapshot)
	}
}

func TestStoreIgnoresAlreadyExpiredNewSessions(t *testing.T) {
	now := time.Date(2026, 8, 18, 14, 0, 0, 0, time.UTC)
	for _, test := range []struct {
		name     string
		phase    Phase
		age      time.Duration
		expected bool
		response bool
		request  string
	}{
		{name: "old completion", phase: PhaseCompleted, age: completedRetention, expected: false},
		{name: "old processing", phase: PhaseProcessing, age: idleRetention, expected: false},
		{name: "fresh completion", phase: PhaseCompleted, age: completedRetention - time.Second, expected: true},
		{name: "old attention", phase: PhaseWaitingInput, age: 72 * time.Hour, expected: true},
		{name: "old action", phase: PhaseProcessing, age: idleRetention, expected: true, response: true, request: "request"},
		{name: "old response without id", phase: PhaseProcessing, age: idleRetention, expected: true, response: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			store := NewStore()
			event := Event{
				Provider: "codex", Profile: "codex", SessionID: "thread",
				Event: "rollout", Phase: test.phase, Source: SourceRollout,
				OccurredAt: now.Add(-test.age), ExpectsResponse: test.response,
				RequestID: test.request, ActionKind: "approval", ActionContext: "ls", CompleteContext: true,
			}
			snapshot, changed := store.Apply(event, now)
			if changed != test.expected || (len(snapshot.Sessions) == 1) != test.expected {
				t.Fatalf("changed=%v snapshot=%#v", changed, snapshot)
			}
		})
	}
}

func TestSnapshotUsesEmptyArraysAcrossTheSwiftBoundary(t *testing.T) {
	store := NewStore()
	now := time.Now().UTC()
	store.Apply(Event{Provider: "codex", Profile: "codex", SessionID: "one",
		Event: "idle", Source: SourceAppServer, OccurredAt: now}, now)
	data, err := json.Marshal(store.Snapshot(now))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"messages":[]`) {
		t.Fatalf("empty messages encoded as null: %s", data)
	}
}

func TestRedactionSuppressesUnsafeAction(t *testing.T) {
	event := Event{ExpectsResponse: true, RequestID: "request", ActionKind: "approval",
		ActionContext:   "curl -H 'Authorization: Bearer secret-value' https://example.test",
		CompleteContext: true}
	if action := safeAction(event); action != nil {
		t.Fatalf("unsafe action remained actionable: %#v", action)
	}
	redacted := BoundDisplayText("TOKEN=abc Bearer xyz", 100)
	if strings.Contains(redacted, "abc") || strings.Contains(redacted, "xyz") {
		t.Fatalf("secret remained: %q", redacted)
	}
}

func TestCancelActionRetractsDisconnectedRequest(t *testing.T) {
	store := NewStore()
	now := time.Now().UTC()
	snapshot, _ := store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "one",
		Event: "PermissionRequest", Source: SourceHook, OccurredAt: now, RequestID: "request",
		ActionKind: "approval", ActionContext: "ls", CompleteContext: true, ExpectsResponse: true}, now)
	if snapshot.Sessions[0].Action == nil {
		t.Fatal("action missing")
	}
	snapshot, changed := store.CancelAction("claude:one", "request", now.Add(time.Second))
	if !changed || snapshot.Sessions[0].Action != nil || snapshot.Sessions[0].Phase != PhaseIdle {
		t.Fatalf("disconnected action retained: %#v", snapshot.Sessions[0])
	}
}

func TestActionTransitionsNormalizeZeroTime(t *testing.T) {
	store := NewStore()
	now := timeForTest()
	snapshot, _ := store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "one",
		Event: "PermissionRequest", Source: SourceHook, OccurredAt: now, RequestID: "resolve",
		ActionKind: "approval", ActionContext: "ls", CompleteContext: true, ExpectsResponse: true}, now)
	request := ActionRequest{Schema: ActionSchema, SessionID: "claude:one", RequestID: "resolve",
		Revision: snapshot.Sessions[0].Revision, Action: "deny"}
	resolved := store.ResolveAction(request, time.Time{})
	if resolved.GeneratedAt.IsZero() || resolved.Sessions[0].UpdatedAt.IsZero() {
		t.Fatalf("resolve action retained a zero timestamp: %#v", resolved)
	}
	cancelStore := NewStore()
	cancelStore.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "one",
		Event: "PermissionRequest", Source: SourceHook, OccurredAt: now, RequestID: "cancel",
		ActionKind: "approval", ActionContext: "pwd", CompleteContext: true, ExpectsResponse: true}, now)
	canceled, changed := cancelStore.CancelAction("claude:one", "cancel", time.Time{})
	if !changed || canceled.GeneratedAt.IsZero() || canceled.Sessions[0].UpdatedAt.IsZero() {
		t.Fatalf("cancel action retained a zero timestamp: %#v", canceled)
	}
}

func TestAuthoritativeNonActionEventClearsPendingAttention(t *testing.T) {
	for _, test := range []struct {
		name          string
		initialSource Source
		nextSource    Source
	}{
		{name: "same authority", initialSource: SourceHook, nextSource: SourceHook},
		{name: "higher authority", initialSource: SourceAppServer, nextSource: SourceHook},
	} {
		t.Run(test.name, func(t *testing.T) {
			now := timeForTest()
			store := NewStore()
			pending, _ := store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "one",
				Event: "PermissionRequest", Source: test.initialSource, OccurredAt: now, RequestID: "request",
				ActionKind: "approval", ActionContext: "ls", CompleteContext: true, ExpectsResponse: true}, now)
			priorAction := pending.Sessions[0].Action
			if priorAction == nil || !pending.Sessions[0].NeedsAttention() {
				t.Fatalf("pending action fixture is invalid: %#v", pending)
			}
			updated, changed := store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "one",
				Event: "PostToolUse", Phase: PhaseProcessing, Source: test.nextSource,
				OccurredAt: now.Add(time.Second)}, now.Add(time.Second))
			if !changed || len(updated.Sessions) != 1 || !nonActionTransitionComplete(updated.Sessions[0]) {
				t.Fatalf("non-action transition retained attention: %#v", updated)
			}
			staleAction := updated.Sessions[0]
			staleAction.Action = priorAction
			if nonActionTransitionComplete(staleAction) {
				t.Fatal("regression predicate accepted a retained pending action")
			}
		})
	}
}

func nonActionTransitionComplete(session Session) bool {
	return session.Phase == PhaseProcessing && session.Action == nil && !session.NeedsAttention()
}

func TestAnswerPayloadIsBounded(t *testing.T) {
	store := NewStore()
	now := time.Now().UTC()
	snapshot, _ := store.Apply(Event{Provider: "claude", Profile: "claude-code", SessionID: "question",
		Event: "AskUserQuestion", Source: SourceHook, OccurredAt: now, RequestID: "request",
		ActionKind: "question", ActionContext: "Choose", CompleteContext: true, ExpectsResponse: true}, now)
	request := ActionRequest{Schema: ActionSchema, SessionID: "claude:question", RequestID: "request",
		Revision: snapshot.Sessions[0].Revision, Action: "answer", Answers: map[string][]string{"answer": {strings.Repeat("x", maxActionRunes+1)}}}
	if _, err := store.ValidateAction(request); !errors.Is(err, ErrInvalidAction) {
		t.Fatalf("oversized answer accepted: %v", err)
	}
	request.Answers = map[string][]string{"answer": {"yes"}}
	if _, err := store.ValidateAction(request); err != nil {
		t.Fatalf("valid answer rejected: %v", err)
	}
}
