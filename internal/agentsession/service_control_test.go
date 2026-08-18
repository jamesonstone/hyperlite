package agentsession

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestServiceIntegrationSelfTestTraversesSocketStoreAndProjection(t *testing.T) {
	home := t.TempDir()
	runtimeDir := filepath.Join("/tmp", fmt.Sprintf("hl-agent-selftest-%d-%d", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.RemoveAll(runtimeDir) })
	socketPath := filepath.Join(runtimeDir, "agent.sock")
	inputReader, inputWriter := io.Pipe()
	outputReader, outputWriter := io.Pipe()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		done <- RunService(ctx, inputReader, outputWriter, io.Discard, ServiceOptions{
			SocketPath: socketPath, Home: home, DisableCodex: true,
			Environment: map[string]string{"XDG_STATE_HOME": filepath.Join(home, "state")},
		})
	}()
	decoder := json.NewDecoder(outputReader)
	var initial Snapshot
	if err := decodeAgentSnapshot(decoder, &initial); err != nil || initial.Schema != SnapshotSchema {
		t.Fatalf("initial snapshot = %#v err=%v", initial, err)
	}
	waitForSocket(t, socketPath)
	control := ControlRequest{Schema: ControlSchema, Operation: ControlIntegrationTest,
		Profile: "claude-code", RequestID: "self-test-1"}
	if err := json.NewEncoder(inputWriter).Encode(control); err != nil {
		t.Fatal(err)
	}
	type evidence struct {
		synthetic bool
		removed   bool
		passed    bool
		err       error
	}
	evidenceChannel := make(chan evidence, 1)
	go func() {
		result := evidence{}
		for !result.synthetic || !result.removed || !result.passed {
			var raw json.RawMessage
			if err := decoder.Decode(&raw); err != nil {
				result.err = err
				break
			}
			var envelope struct {
				Schema string `json:"schema"`
			}
			if json.Unmarshal(raw, &envelope) != nil {
				continue
			}
			switch envelope.Schema {
			case SnapshotSchema:
				var snapshot Snapshot
				if json.Unmarshal(raw, &snapshot) != nil {
					continue
				}
				found := false
				for _, session := range snapshot.Sessions {
					if session.Synthetic && session.SessionID == "hyperlite-self-test-self-test-1" {
						found = true
					}
				}
				if found {
					result.synthetic = true
				} else if result.synthetic {
					result.removed = true
				}
			case HealthSchema:
				var health IntegrationHealth
				if json.Unmarshal(raw, &health) == nil && health.Profile == "claude-code" &&
					health.SelfTestResult == "passed" {
					result.passed = true
				}
			}
		}
		evidenceChannel <- result
	}()
	select {
	case result := <-evidenceChannel:
		if result.err != nil || !result.synthetic || !result.removed || !result.passed {
			t.Fatalf("self-test evidence = %#v", result)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("self-test projection timed out")
	}
	_ = inputWriter.Close()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("self-test service did not stop")
	}
}

func TestServiceInputAcceptsV1AndV2Actions(t *testing.T) {
	for _, schema := range []string{ActionSchemaV1, ActionSchema} {
		request := ActionRequest{Schema: schema, Provider: "claude", SessionID: "claude:one",
			RequestID: "request", Revision: 1, Action: "deny"}
		data, err := json.Marshal(request)
		if err != nil {
			t.Fatal(err)
		}
		data = append(data, '\n')
		output := make(chan serviceInput, 1)
		errors := make(chan error, 1)
		readServiceInput(context.Background(), bytes.NewReader(data), output, errors)
		select {
		case decoded := <-output:
			if decoded.action == nil || decoded.action.Schema != schema {
				t.Fatalf("action schema %q was not decoded: %#v", schema, decoded)
			}
		default:
			t.Fatalf("action schema %q did not reach service input", schema)
		}
	}
}
