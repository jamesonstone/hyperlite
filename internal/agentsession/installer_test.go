package agentsession

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestJSONIntegrationPreservesUnrelatedConfiguration(t *testing.T) {
	home := t.TempDir()
	path := filepath.Join(home, ".claude", "settings.json")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	original := []byte(`{"theme":"dark","hooks":{"Stop":[{"command":"other"}]}}`)
	if err := os.WriteFile(path, original, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReconcileIntegration(home, "/Applications/Hyperlite.app/Contents/MacOS/hyperlite-cli", "claude-code", true); err != nil {
		t.Fatalf("enable integration: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	if document["theme"] != "dark" || !strings.Contains(string(data), "other") || !strings.Contains(string(data), "hyperlite_managed") {
		t.Fatalf("unexpected enabled config: %s", data)
	}
	if _, err := ReconcileIntegration(home, "/Applications/Hyperlite.app/Contents/MacOS/hyperlite-cli", "claude-code", false); err != nil {
		t.Fatalf("disable integration: %v", err)
	}
	data, _ = os.ReadFile(path)
	if strings.Contains(string(data), "hyperlite_managed") || !strings.Contains(string(data), "other") || !strings.Contains(string(data), `"theme": "dark"`) {
		t.Fatalf("unexpected disabled config: %s", data)
	}
}

func TestTOMLIntegrationUsesOwnedBlock(t *testing.T) {
	home := t.TempDir()
	path := filepath.Join(home, ".kimi-code", "config.toml")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("model = \"moonshot\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReconcileIntegration(home, "/app/hyperlite-cli", "kimi", true); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	if !strings.Contains(string(data), string(tomlBegin)) || !strings.Contains(string(data), "moonshot") {
		t.Fatalf("%s", data)
	}
	if _, err := ReconcileIntegration(home, "/app/hyperlite-cli", "kimi", false); err != nil {
		t.Fatal(err)
	}
	data, _ = os.ReadFile(path)
	if strings.Contains(string(data), string(tomlBegin)) || !strings.Contains(string(data), "moonshot") {
		t.Fatalf("%s", data)
	}
}

func TestIntegrationRejectsSymlinkTarget(t *testing.T) {
	home := t.TempDir()
	outside := filepath.Join(t.TempDir(), "settings.json")
	if err := os.WriteFile(outside, []byte(`{}`), 0o600); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(home, ".claude", "settings.json")
	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, target); err != nil {
		t.Fatal(err)
	}
	if _, err := ReconcileIntegration(home, "/app/hyperlite-cli", "claude-code", true); err == nil {
		t.Fatal("symlink target was accepted")
	}
}

func TestIntegrationRejectsMalformedAndConcurrentSharedConfig(t *testing.T) {
	home := t.TempDir()
	path := filepath.Join(home, ".claude", "settings.json")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(`{"hooks":`), 0o600); err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(path)
	if _, err := ReconcileIntegration(home, "/app/hyperlite-cli", "claude-code", true); err == nil {
		t.Fatal("malformed shared config was overwritten")
	}
	after, _ := os.ReadFile(path)
	if string(after) != string(before) {
		t.Fatal("malformed shared config changed")
	}
	if err := os.WriteFile(path, []byte(`{}`), 0o600); err != nil {
		t.Fatal(err)
	}
	_, signature, err := readConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(`{"other":true}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := writeConfig(path, []byte(`{"hyperlite":true}`), signature); err == nil {
		t.Fatal("concurrent config change was overwritten")
	}
}

func TestGeneratedIntegrationOwnershipIsRecoverable(t *testing.T) {
	home := t.TempDir()
	if _, err := ReconcileIntegration(home, "/app/hyperlite-cli", "opencode", true); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(home, ".config", "opencode", "plugins", "hyperlite.js")
	data, err := os.ReadFile(path)
	if err != nil || !strings.Contains(string(data), "HYPERLITE MANAGED") {
		t.Fatalf("generated plugin: %s %v", data, err)
	}
	if _, err := ReconcileIntegration(home, "/app/hyperlite-cli", "opencode", false); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("owned plugin was not removed")
	}
	if err := os.WriteFile(path, []byte("user plugin"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReconcileIntegration(home, "/app/hyperlite-cli", "opencode", false); err == nil {
		t.Fatal("unowned plugin was removed")
	}
}

func TestBridgeCommandQuotesApplicationPaths(t *testing.T) {
	command := bridgeCommand("/Applications/Hyper Lite.app/Contents/MacOS/hyperlite-cli", "claude-code")
	if command != "'/Applications/Hyper Lite.app/Contents/MacOS/hyperlite-cli' agent hook --profile 'claude-code'" {
		t.Fatalf("unsafe bridge command: %q", command)
	}
}

func TestRoutingStorePrunesContentFreeRecords(t *testing.T) {
	now := timeForTest()
	path := filepath.Join(t.TempDir(), "state", "agent-routing.json")
	records := []RoutingRecord{{Provider: "codex", Profile: "codex", SessionID: "one",
		Routing: Routing{WorkspacePath: "/tmp/project"}, LastSeen: now}}
	if err := SaveRouting(path, records, now); err != nil {
		t.Fatal(err)
	}
	loaded, err := LoadRouting(path, now.Add(time.Hour))
	if err != nil || len(loaded) != 1 {
		t.Fatalf("load routing: %#v %v", loaded, err)
	}
	if loaded[0].Routing.WorkspacePath != "/tmp/project" {
		t.Fatalf("unexpected routing: %#v", loaded[0])
	}
	loaded, err = LoadRouting(path, now.Add(25*time.Hour))
	if err != nil || len(loaded) != 0 {
		t.Fatalf("expired routing retained: %#v %v", loaded, err)
	}
}

func timeForTest() time.Time {
	return time.Date(2026, 8, 17, 12, 0, 0, 0, time.UTC)
}
