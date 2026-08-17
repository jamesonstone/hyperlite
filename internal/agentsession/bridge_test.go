package agentsession

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestProviderResponseIsCapabilityGated(t *testing.T) {
	allowed := ProviderResponse("claude-code", "approval", HookDecision{RequestID: "one", Action: "allow_once"})
	output, _ := allowed["hookSpecificOutput"].(map[string]any)
	decision, _ := output["decision"].(map[string]any)
	if decision["behavior"] != "allow" {
		t.Fatalf("unexpected Claude response: %#v", allowed)
	}
	if got := ProviderResponse("gemini", "approval", HookDecision{Action: "allow_once"}); got != nil {
		t.Fatalf("notify-only integration returned an action: %#v", got)
	}
	answer := ProviderResponse("qwen-code", "question", HookDecision{
		Action: "answer", Answers: map[string][]string{"question": {"yes"}},
	})
	if answer["decision"] != "answer" {
		t.Fatalf("unexpected answer response: %#v", answer)
	}
}

func TestRuntimeSocketIsUserOnly(t *testing.T) {
	directory := filepath.Join("/tmp", "hyperlite-agent-permissions-"+t.Name())
	_ = os.RemoveAll(directory)
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	path := filepath.Join(directory, "agent.sock")
	listener, err := PrepareRuntimeSocket(path)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	directoryInfo, err := os.Stat(directory)
	if err != nil {
		t.Fatal(err)
	}
	socketInfo, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if directoryInfo.Mode().Perm() != 0o700 || socketInfo.Mode().Perm() != 0o600 {
		t.Fatalf("permissions directory=%#o socket=%#o", directoryInfo.Mode().Perm(), socketInfo.Mode().Perm())
	}
}

func TestRuntimeSocketRejectsOverlongPath(t *testing.T) {
	path := "/tmp/" + string(make([]byte, 110))
	if _, err := PrepareRuntimeSocket(path); err == nil {
		t.Fatal("overlong Unix socket path was accepted")
	}
}

func TestRuntimeSocketDoesNotReplaceLiveService(t *testing.T) {
	directory := filepath.Join("/tmp", "hyperlite-agent-live-"+t.Name())
	_ = os.RemoveAll(directory)
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	path := filepath.Join(directory, "agent.sock")
	listener, err := PrepareRuntimeSocket(path)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	accepted := make(chan struct{})
	go func() {
		connection, acceptErr := listener.Accept()
		if acceptErr == nil {
			connection.Close()
		}
		close(accepted)
	}()
	if _, err := PrepareRuntimeSocket(path); err == nil {
		t.Fatal("second service replaced a live socket")
	}
	select {
	case <-accepted:
	case <-time.After(time.Second):
		t.Fatal("live socket probe did not connect")
	}
	if _, err := os.Lstat(path); err != nil {
		t.Fatalf("live socket disappeared: %v", err)
	}
}
