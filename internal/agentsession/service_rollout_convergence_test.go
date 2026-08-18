package agentsession

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestServiceLargeRolloutConvergesWithoutReadmissionLoop(t *testing.T) {
	home := t.TempDir()
	now := time.Now()
	freshRow := func(kind, payload string) string {
		return fmt.Sprintf(`{"timestamp":%q,"type":%q,"payload":%s}`, now.UTC().Format(time.RFC3339Nano), kind, payload)
	}
	directory := codexDateDirectory(home, now)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(home, "bin"), 0o700); err != nil {
		t.Fatal(err)
	}
	lines := []string{freshRow("session_meta", `{"id":"thread-large","cwd":"/tmp/project"}`)}
	for index := 0; index < 2_000; index++ {
		lines = append(lines, freshRow("event_msg", fmt.Sprintf(`{"type":"user_message","message":"row-%d"}`, index)))
	}
	lines = append(lines, freshRow("event_msg", `{"type":"task_started"}`))
	writeRollout(t, filepath.Join(directory, "large.jsonl"), lines...)
	inputReader, inputWriter := io.Pipe()
	outputReader, outputWriter := io.Pipe()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	runtimeDir := filepath.Join("/tmp", fmt.Sprintf("hl-agent-converge-%d-%d", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.RemoveAll(runtimeDir) })
	go func() {
		defer func() { _ = outputWriter.Close() }()
		done <- RunService(ctx, inputReader, outputWriter, io.Discard, ServiceOptions{
			SocketPath: filepath.Join(runtimeDir, "agent.sock"), Home: home,
			Environment: map[string]string{"HOME": home, "PATH": filepath.Join(home, "bin"), "XDG_STATE_HOME": filepath.Join(home, "state")},
		})
	}()
	decoder := json.NewDecoder(outputReader)
	converged := make(chan Snapshot, 1)
	go func() {
		reported := false
		for {
			var snapshot Snapshot
			if err := decodeAgentSnapshot(decoder, &snapshot); err != nil {
				return
			}
			for _, session := range snapshot.Sessions {
				if !reported && session.SessionID == "thread-large" && session.Phase == PhaseProcessing {
					converged <- snapshot
					reported = true
				}
			}
		}
	}()
	select {
	case snapshot := <-converged:
		if len(snapshot.Sessions) != 1 || len(snapshot.Sessions[0].Messages) != maxMessages {
			t.Fatalf("converged snapshot = %#v", snapshot)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("large rollout did not converge")
	}
	_ = inputWriter.Close()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("owner EOF blocked after rollout convergence")
	}
}
