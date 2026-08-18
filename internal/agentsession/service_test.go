package agentsession

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestServiceRoundTripUsesExactLiveResponseChannel(t *testing.T) {
	temp := t.TempDir()
	runtimeDir := filepath.Join("/tmp", fmt.Sprintf("hl-agent-test-%d-%d", os.Getpid(), time.Now().UnixNano()))
	socketPath := filepath.Join(runtimeDir, "agent.sock")
	t.Cleanup(func() { _ = os.RemoveAll(runtimeDir) })
	inputReader, inputWriter := io.Pipe()
	outputReader, outputWriter := io.Pipe()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	serviceDone := make(chan error, 1)
	go func() {
		serviceDone <- RunService(ctx, inputReader, outputWriter, io.Discard, ServiceOptions{
			SocketPath: socketPath, Home: temp,
			Environment:  map[string]string{"XDG_STATE_HOME": filepath.Join(temp, "state")},
			DisableCodex: true,
		})
	}()
	decoder := json.NewDecoder(outputReader)
	type initialResult struct {
		snapshot Snapshot
		err      error
	}
	initialChannel := make(chan initialResult, 1)
	go func() {
		var snapshot Snapshot
		err := decoder.Decode(&snapshot)
		initialChannel <- initialResult{snapshot: snapshot, err: err}
	}()
	var initial Snapshot
	select {
	case result := <-initialChannel:
		initial = result.snapshot
		if result.err != nil || initial.Schema != SnapshotSchema {
			t.Fatalf("initial snapshot: %#v %v", initial, result.err)
		}
	case err := <-serviceDone:
		t.Fatalf("service stopped before initial snapshot: %v", err)
	case <-time.After(2 * time.Second):
		t.Fatal("initial snapshot timed out")
	}
	waitForSocket(t, socketPath)
	connection, err := (&net.Dialer{}).DialContext(ctx, "unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	event := Event{Schema: EventSchema, Provider: "claude", Profile: "claude-code",
		SessionID: "session-1", Event: "PermissionRequest", Source: SourceHook,
		OccurredAt: time.Now().UTC(), RequestID: "request-1", ActionKind: "approval",
		ActionContext: "git status --short", CompleteContext: true, ExpectsResponse: true,
		MessageRole: "user", Message: "ephemeral-secret-fixture"}
	if err := json.NewEncoder(connection).Encode(event); err != nil {
		t.Fatal(err)
	}
	var active Snapshot
	if err := decoder.Decode(&active); err != nil || len(active.Sessions) != 1 {
		t.Fatalf("active snapshot: %#v %v", active, err)
	}
	session := active.Sessions[0]
	request := ActionRequest{Schema: ActionSchema, SessionID: session.ID,
		RequestID: "request-1", Revision: session.Revision, Action: "allow_once"}
	if err := json.NewEncoder(inputWriter).Encode(request); err != nil {
		t.Fatal(err)
	}
	var decision HookDecision
	if err := json.NewDecoder(connection).Decode(&decision); err != nil {
		t.Fatal(err)
	}
	if decision.RequestID != request.RequestID || decision.Action != "allow_once" {
		t.Fatalf("unexpected decision: %#v", decision)
	}
	var resolved Snapshot
	if err := decoder.Decode(&resolved); err != nil || resolved.Sessions[0].Action != nil {
		t.Fatalf("resolved snapshot: %#v %v", resolved, err)
	}
	var result ActionResult
	if err := decoder.Decode(&result); err != nil || result.Status != "submitted" {
		t.Fatalf("action result: %#v %v", result, err)
	}
	routingData, err := os.ReadFile(filepath.Join(temp, "state", "hyperlite", "agent-routing.json"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(routingData, []byte("ephemeral-secret-fixture")) {
		t.Fatalf("session content persisted in routing state: %s", routingData)
	}
	_ = connection.Close()
	cancel()
	_ = inputWriter.Close()
	_ = outputReader.Close()
	select {
	case err := <-serviceDone:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("service did not stop")
	}
}

func TestSendHookFailsOpenWithoutService(t *testing.T) {
	event := Event{Schema: EventSchema, Provider: "claude", Profile: "claude-code",
		SessionID: "one", RequestID: "request", ActionKind: "approval",
		CompleteContext: true, ExpectsResponse: true}
	if err := SendHook(event, filepath.Join(t.TempDir(), "missing.sock"), time.Second, io.Discard); err != nil {
		t.Fatalf("unavailable service should fail open: %v", err)
	}
}

func TestServiceStopsWhenOwningAppClosesInput(t *testing.T) {
	runtimeDir := filepath.Join("/tmp", fmt.Sprintf("hl-agent-eof-%d-%d", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.RemoveAll(runtimeDir) })
	inputReader, inputWriter := io.Pipe()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		done <- RunService(ctx, inputReader, io.Discard, io.Discard, ServiceOptions{
			SocketPath: filepath.Join(runtimeDir, "agent.sock"), Home: t.TempDir(),
			Environment: map[string]string{"XDG_STATE_HOME": t.TempDir()}, DisableCodex: true,
		})
	}()
	waitForSocket(t, filepath.Join(runtimeDir, "agent.sock"))
	_ = inputWriter.Close()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("service remained after owner input closed")
	}
}

func TestServiceRetractsActionWhenProviderDisconnects(t *testing.T) {
	runtimeDir := filepath.Join("/tmp", fmt.Sprintf("hl-agent-close-%d-%d", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.RemoveAll(runtimeDir) })
	inputReader, inputWriter := io.Pipe()
	outputReader, outputWriter := io.Pipe()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		done <- RunService(ctx, inputReader, outputWriter, io.Discard, ServiceOptions{
			SocketPath: filepath.Join(runtimeDir, "agent.sock"), Home: t.TempDir(),
			Environment: map[string]string{"XDG_STATE_HOME": t.TempDir()}, DisableCodex: true,
		})
	}()
	decoder := json.NewDecoder(outputReader)
	var initial Snapshot
	if err := decoder.Decode(&initial); err != nil {
		t.Fatal(err)
	}
	waitForSocket(t, filepath.Join(runtimeDir, "agent.sock"))
	connection, err := (&net.Dialer{}).DialContext(ctx, "unix", filepath.Join(runtimeDir, "agent.sock"))
	if err != nil {
		t.Fatal(err)
	}
	event := Event{Schema: EventSchema, Provider: "claude", Profile: "claude-code",
		SessionID: "disconnect", Event: "PermissionRequest", Source: SourceHook,
		OccurredAt: time.Now().UTC(), RequestID: "request", ActionKind: "approval",
		ActionContext: "ls", CompleteContext: true, ExpectsResponse: true}
	if err := json.NewEncoder(connection).Encode(event); err != nil {
		t.Fatal(err)
	}
	var active Snapshot
	if err := decoder.Decode(&active); err != nil || active.Sessions[0].Action == nil {
		t.Fatalf("active request: %#v %v", active, err)
	}
	_ = connection.Close()
	var retracted Snapshot
	if err := decoder.Decode(&retracted); err != nil || retracted.Sessions[0].Action != nil || retracted.Sessions[0].Phase != PhaseIdle {
		t.Fatalf("retracted request: %#v %v", retracted, err)
	}
	_ = inputWriter.Close()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("service did not stop")
	}
}

func TestOwnerEOFStopsOwnedCodexProcess(t *testing.T) {
	temp := t.TempDir()
	pidFile := filepath.Join(temp, "codex.pid")
	t.Setenv("TEST_CODEX_PID_FILE", pidFile)
	executable := filepath.Join(temp, "codex")
	script := `#!/bin/sh
IFS= read -r initialize
printf '%s\n' '{"id":1,"result":{}}'
IFS= read -r initialized
IFS= read -r list
printf '%s\n' '{"id":2,"result":{"data":[]}}'
printf '%s' "$$" > "$TEST_CODEX_PID_FILE"
while :; do sleep 1; done
`
	if err := os.WriteFile(executable, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	inputReader, inputWriter := io.Pipe()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	runtimeDir := filepath.Join("/tmp", fmt.Sprintf("hl-agent-codex-%d-%d", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.RemoveAll(runtimeDir) })
	go func() {
		done <- RunService(ctx, inputReader, io.Discard, io.Discard, ServiceOptions{
			SocketPath: filepath.Join(runtimeDir, "agent.sock"), Home: temp,
			Environment: map[string]string{"HOME": temp, "PATH": temp, "XDG_STATE_HOME": filepath.Join(temp, "state")},
		})
	}()
	waitForFile(t, pidFile)
	data, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		t.Fatal(err)
	}
	_ = inputWriter.Close()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("service did not stop")
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && syscall.Kill(pid, 0) == nil {
		time.Sleep(10 * time.Millisecond)
	}
	if syscall.Kill(pid, 0) == nil {
		t.Fatalf("owned Codex process %d remained", pid)
	}
}

func waitForSocket(t *testing.T, path string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSocket != 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("socket did not appear: %s", path)
}

func waitForFile(t *testing.T, path string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("file did not appear: %s", path)
}
