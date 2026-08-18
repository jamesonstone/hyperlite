package agentsession

import (
	"context"
	"os/exec"
	"runtime"
	"testing"
	"time"
)

func TestExactProcessWatcherUsesPIDAndStartToken(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("Darwin process events only")
	}
	command := exec.Command("/bin/sleep", "0.1")
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	token, err := ProcessStartToken(command.Process.Pid)
	if err != nil || token == "" {
		_ = command.Process.Kill()
		t.Fatalf("process token = %q err=%v", token, err)
	}
	done := make(chan error, 1)
	go func() { done <- WatchExactProcessExit(context.Background(), command.Process.Pid, token) }()
	_ = command.Wait()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("process exit was not observed")
	}
}

func TestExactProcessWatcherRejectsWrongStartToken(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("Darwin process events only")
	}
	command := exec.Command("/bin/sleep", "1")
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = command.Process.Kill()
		_ = command.Wait()
	}()
	if err := WatchExactProcessExit(context.Background(), command.Process.Pid, "wrong"); err == nil {
		t.Fatal("wrong process start token was accepted")
	}
}

func TestProcessLivenessDoesNotRegisterInvalidProof(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("Darwin process proof only")
	}
	liveness := NewProcessLiveness(context.Background(), nil)
	if liveness.Observe(Event{Provider: "codex", SessionID: "one",
		ProcessID: 999999, ProcessStart: "invalid"}) || liveness.Count() != 0 {
		t.Fatal("invalid process proof was retained")
	}
}
