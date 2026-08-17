package cli

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/agentsession"
)

func TestAgentIntegrationsListDoesNotRequireProjectConfig(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	var output bytes.Buffer
	app := App{In: bytes.NewBuffer(nil), Out: &output, Err: &bytes.Buffer{}}
	command := app.Root()
	command.SetArgs([]string{"agent", "integrations", "list"})
	if err := command.Execute(); err != nil {
		t.Fatalf("list integrations: %v", err)
	}
	var values []agentsession.IntegrationStatus
	if err := json.Unmarshal(output.Bytes(), &values); err != nil {
		t.Fatalf("decode integrations: %v", err)
	}
	if len(values) != len(agentsession.Profiles()) {
		t.Fatalf("integration count = %d", len(values))
	}
}

func TestAgentHookFailsOpenWhenAppIsUnavailable(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("TMPDIR", filepath.Join(t.TempDir(), "runtime"))
	input := bytes.NewBufferString(`{"session_id":"one","hook_event_name":"PermissionRequest","tool_use_id":"request","tool_input":{"command":"git status"}}`)
	var output bytes.Buffer
	app := App{In: input, Out: &output, Err: &bytes.Buffer{}}
	command := app.Root()
	command.SetArgs([]string{"agent", "hook", "--profile", "claude-code", "--wait-seconds", "1"})
	if err := command.Execute(); err != nil {
		t.Fatalf("hook should fail open: %v", err)
	}
	if output.Len() != 0 {
		t.Fatalf("unavailable app emitted a provider decision: %s", output.String())
	}
}
