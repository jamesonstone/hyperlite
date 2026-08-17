package agentsession

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

type HookDecision struct {
	RequestID string              `json:"request_id"`
	Action    string              `json:"action"`
	Answers   map[string][]string `json:"answers,omitempty"`
}

func RuntimeSocketPath(environment map[string]string) string {
	root := environment["TMPDIR"]
	if root == "" {
		root = os.TempDir()
	}
	return filepath.Join(root, "hyperlite-agent-"+strconv.Itoa(os.Getuid()), "agent.sock")
}

func PrepareRuntimeSocket(path string) (net.Listener, error) {
	if len([]byte(path)) >= 104 {
		return nil, errors.New("agent socket path exceeds the Unix socket limit")
	}
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return nil, fmt.Errorf("create agent runtime directory: %w", err)
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return nil, fmt.Errorf("secure agent runtime directory: %w", err)
	}
	if info, err := os.Lstat(path); err == nil {
		if info.Mode()&os.ModeSocket == 0 {
			return nil, errors.New("agent socket path is occupied by a non-socket")
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok || int(stat.Uid) != os.Getuid() {
			return nil, errors.New("stale agent socket is not user-owned")
		}
		if connection, dialErr := net.DialTimeout("unix", path, 100*time.Millisecond); dialErr == nil {
			connection.Close()
			return nil, errors.New("another Hyperlite agent service is already active")
		}
		if err := os.Remove(path); err != nil {
			return nil, fmt.Errorf("remove stale agent socket: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("inspect agent socket path: %w", err)
	}
	listener, err := net.Listen("unix", path)
	if err != nil {
		return nil, fmt.Errorf("listen on agent socket: %w", err)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		listener.Close()
		return nil, fmt.Errorf("secure agent socket: %w", err)
	}
	return listener, nil
}

func SendHook(event Event, socketPath string, timeout time.Duration, out io.Writer) error {
	connection, err := net.DialTimeout("unix", socketPath, 500*time.Millisecond)
	if err != nil {
		return nil
	}
	defer connection.Close()
	if timeout <= 0 {
		timeout = 24 * time.Hour
	}
	_ = connection.SetDeadline(time.Now().Add(timeout))
	if err := json.NewEncoder(connection).Encode(event); err != nil {
		return nil
	}
	var decision HookDecision
	if err := json.NewDecoder(bufio.NewReader(connection)).Decode(&decision); err != nil {
		return nil
	}
	if decision.RequestID != event.RequestID || decision.Action == "" {
		return nil
	}
	response := ProviderResponse(event.Profile, event.ActionKind, decision)
	if response == nil {
		return nil
	}
	return json.NewEncoder(out).Encode(response)
}

func ProviderResponse(profileID, actionKind string, decision HookDecision) map[string]any {
	profile, ok := ProfileByID(profileID)
	if !ok || profile.ActionMode != "blocking" {
		return nil
	}
	if actionKind == "question" && decision.Action == "answer" {
		return map[string]any{"decision": "answer", "answers": decision.Answers}
	}
	if actionKind != "approval" {
		return nil
	}
	behavior := "deny"
	if decision.Action == "allow_once" {
		behavior = "allow"
	} else if decision.Action != "deny" {
		return nil
	}
	if profileID == "codex" {
		return map[string]any{"decision": behavior}
	}
	return map[string]any{
		"hookSpecificOutput": map[string]any{
			"hookEventName": "PermissionRequest",
			"decision":      map[string]any{"behavior": behavior},
		},
	}
}
