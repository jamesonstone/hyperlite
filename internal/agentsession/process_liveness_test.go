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
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, "/bin/sleep", "0.1")
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	token, err := ProcessStartToken(command.Process.Pid)
	if err != nil || token == "" {
		_ = command.Process.Kill()
		t.Fatalf("process token = %q err=%v", token, err)
	}
	done := make(chan error, 1)
	go func() { done <- WatchExactProcessExit(ctx, command.Process.Pid, token) }()
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
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, "/bin/sleep", "1")
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = command.Process.Kill()
		_ = command.Wait()
	}()
	if err := WatchExactProcessExit(ctx, command.Process.Pid, "wrong"); err == nil {
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

func TestProcessLivenessSuppressesSupersededExit(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("Darwin process proof only")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, "/bin/sleep", "0.1")
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	token, err := ProcessStartToken(command.Process.Pid)
	if err != nil {
		t.Fatal(err)
	}
	exited := make(chan string, 1)
	liveness := NewProcessLiveness(ctx, func(id string) { exited <- id })
	if !liveness.Observe(Event{Provider: "codex", SessionID: "one",
		ProcessID: command.Process.Pid, ProcessStart: token}) {
		t.Fatal("valid proof was rejected")
	}
	liveness.mu.Lock()
	liveness.proofs["codex:one"] = processProof{pid: command.Process.Pid + 1, token: "replacement", cancel: func() {}}
	liveness.mu.Unlock()
	_ = command.Wait()
	select {
	case id := <-exited:
		t.Fatalf("superseded proof emitted exit for %q", id)
	case <-time.After(200 * time.Millisecond):
	}
	liveness.Close()
}
