package agentsession

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestNormalizeHookBuildsBoundedExactApproval(t *testing.T) {
	profile, _ := ProfileByID("claude-code")
	payload := map[string]any{
		"session_id": "session-1", "hook_event_name": "PermissionRequest",
		"tool_use_id": "tool-1", "tool_name": "Bash", "cwd": "/tmp/project",
		"tool_input": map[string]any{
			"command": "git status --short", "authorization": "Bearer hidden",
		},
	}
	raw, _ := json.Marshal(payload)
	event, err := NormalizeHook(profile, raw, map[string]string{}, time.Now().UTC())
	if err != nil {
		t.Fatalf("normalize hook: %v", err)
	}
	if event.SessionID != "session-1" || event.RequestID != "tool-1" || !event.ExpectsResponse {
		t.Fatalf("unexpected event: %#v", event)
	}
	if event.CompleteContext {
		t.Fatal("secret-bearing payload should not be complete")
	}
	if event.Arguments["authorization"] != "[REDACTED]" {
		t.Fatalf("authorization was not redacted: %#v", event.Arguments)
	}
}

func TestNormalizeHookRejectsUnidentifiedOrOversizedPayload(t *testing.T) {
	profile, _ := ProfileByID("codex")
	if _, err := NormalizeHook(profile, []byte(`{"event":"Stop"}`), nil, time.Now()); err == nil {
		t.Fatal("missing session id was accepted")
	}
	if _, err := NormalizeHook(profile, []byte(strings.Repeat("x", maxHookPayload+1)), nil, time.Now()); err == nil {
		t.Fatal("oversized payload was accepted")
	}
}

func TestNormalizeHookIgnoresReasoning(t *testing.T) {
	profile, _ := ProfileByID("codex")
	raw := []byte(`{"thread_id":"thread-1","event":"agent_reasoning","message":"private"}`)
	event, err := NormalizeHook(profile, raw, nil, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if event.Message != "" || event.MessageRole != "" {
		t.Fatalf("reasoning leaked into display event: %#v", event)
	}
}

func TestProviderRegistryContainsFrozenMatrix(t *testing.T) {
	want := []string{"claude-code", "codex", "gemini", "antigravity", "hermes", "pi",
		"qwen-code", "kimi", "openclaw", "opencode", "cursor", "qoder", "qoder-cli",
		"qoder-cn", "qoder-cn-cli", "qoderwork", "codebuddy", "codebuddy-cli",
		"workbuddy", "copilot"}
	for _, id := range want {
		if _, ok := ProfileByID(id); !ok {
			t.Fatalf("missing profile %q", id)
		}
	}
}
