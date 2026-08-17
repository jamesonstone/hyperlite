package agentsession

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const maxAppServerMessage = 8 * 1024 * 1024

type codexRPCMessage struct {
	ID     any            `json:"id,omitempty"`
	Method string         `json:"method,omitempty"`
	Params map[string]any `json:"params,omitempty"`
	Result map[string]any `json:"result,omitempty"`
	Error  map[string]any `json:"error,omitempty"`
}

func MonitorCodex(ctx context.Context, environment map[string]string, emit func(Event)) error {
	executable := resolveCodexExecutable(environment)
	if executable == "" {
		return nil
	}
	command := exec.CommandContext(ctx, executable, "app-server", "--stdio")
	command.Env = os.Environ()
	stdin, err := command.StdinPipe()
	if err != nil {
		return fmt.Errorf("open Codex app-server input: %w", err)
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		return fmt.Errorf("open Codex app-server output: %w", err)
	}
	command.Stderr = io.Discard
	if err := command.Start(); err != nil {
		return fmt.Errorf("start Codex app-server: %w", err)
	}
	defer func() {
		_ = stdin.Close()
		if command.Process != nil {
			_ = command.Process.Kill()
		}
		_ = command.Wait()
	}()
	encoder := json.NewEncoder(stdin)
	reader := bufio.NewScanner(stdout)
	reader.Buffer(make([]byte, 64*1024), maxAppServerMessage)
	if err := encoder.Encode(map[string]any{"id": 1, "method": "initialize", "params": map[string]any{
		"clientInfo": map[string]any{"name": "hyperlite", "title": "Hyperlite", "version": "1"},
	}}); err != nil {
		return err
	}
	if err := readUntilResponse(ctx, reader, 1, emit); err != nil {
		return err
	}
	if err := encoder.Encode(map[string]any{"method": "initialized"}); err != nil {
		return err
	}
	if err := encoder.Encode(map[string]any{"id": 2, "method": "thread/list", "params": map[string]any{
		"limit": 100, "sortKey": "recency_at", "sortDirection": "desc",
		"archived": false, "useStateDbOnly": true,
		"sourceKinds": []string{"cli", "vscode", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther"},
	}}); err != nil {
		return err
	}
	response, err := readResponse(ctx, reader, 2, emit)
	if err != nil {
		return err
	}
	for _, thread := range objectSlice(response.Result["data"]) {
		if event, ok := codexThreadEvent(thread, time.Now().UTC()); ok {
			emit(event)
		}
	}
	for reader.Scan() {
		message, ok := decodeCodexLine(reader.Bytes())
		if !ok {
			continue
		}
		handleCodexNotification(message, emit)
	}
	if err := reader.Err(); err != nil && !errors.Is(ctx.Err(), context.Canceled) {
		return err
	}
	return nil
}

func readUntilResponse(ctx context.Context, reader *bufio.Scanner, id int, emit func(Event)) error {
	_, err := readResponse(ctx, reader, id, emit)
	return err
}

func readResponse(ctx context.Context, reader *bufio.Scanner, id int, emit func(Event)) (codexRPCMessage, error) {
	for reader.Scan() {
		select {
		case <-ctx.Done():
			return codexRPCMessage{}, ctx.Err()
		default:
		}
		message, ok := decodeCodexLine(reader.Bytes())
		if !ok {
			continue
		}
		if message.Method != "" {
			handleCodexNotification(message, emit)
			continue
		}
		if rpcID(message.ID) != strconv.Itoa(id) {
			continue
		}
		if len(message.Error) > 0 {
			return codexRPCMessage{}, errors.New("Codex app-server request failed")
		}
		return message, nil
	}
	if err := reader.Err(); err != nil {
		return codexRPCMessage{}, err
	}
	return codexRPCMessage{}, io.EOF
}

func decodeCodexLine(data []byte) (codexRPCMessage, bool) {
	if len(data) == 0 || len(data) > maxAppServerMessage {
		return codexRPCMessage{}, false
	}
	var message codexRPCMessage
	if json.Unmarshal(data, &message) != nil {
		return codexRPCMessage{}, false
	}
	return message, true
}

func handleCodexNotification(message codexRPCMessage, emit func(Event)) {
	if message.Method == "thread/status/changed" {
		threadID := firstString(message.Params, "threadId", "thread_id")
		status, _ := message.Params["status"].(map[string]any)
		if event, ok := codexStatusEvent(threadID, status, time.Now().UTC()); ok {
			emit(event)
		}
		return
	}
	if strings.Contains(message.Method, "requestApproval") || strings.Contains(message.Method, "requestUserInput") {
		threadID := firstString(message.Params, "threadId", "thread_id")
		kind := "approval"
		if strings.Contains(message.Method, "requestUserInput") {
			kind = "question"
		}
		emit(Event{Schema: EventSchema, Provider: "codex", Profile: "codex", SessionID: threadID,
			Event: message.Method, Phase: PhaseWaitingInput, Source: SourceAppServer,
			OccurredAt: time.Now().UTC(), ActionKind: kind, ActionTitle: "Open in Codex",
			ActionContext: "Codex is waiting in another client", CompleteContext: false,
			ExpectsResponse: false, Routing: Routing{BundleID: "com.openai.codex"}})
	}
}

func codexThreadEvent(thread map[string]any, now time.Time) (Event, bool) {
	threadID := firstString(thread, "id", "threadId")
	status, _ := thread["status"].(map[string]any)
	event, ok := codexStatusEvent(threadID, status, now)
	if !ok {
		return Event{}, false
	}
	event.Title = firstString(thread, "name")
	event.WorkspacePath = firstString(thread, "cwd")
	event.ParentID = firstString(thread, "parentThreadId", "parent_thread_id", "forkedFromId")
	event.RolloutPath = firstString(thread, "rolloutPath", "sessionFilePath", "path")
	event.Routing = Routing{BundleID: "com.openai.codex", WorkspacePath: event.WorkspacePath}
	return event, true
}

func codexStatusEvent(threadID string, status map[string]any, now time.Time) (Event, bool) {
	if threadID == "" {
		return Event{}, false
	}
	typeName := firstString(status, "type")
	phase := PhaseIdle
	source := SourceAppServer
	switch typeName {
	case "active":
		phase = PhaseProcessing
		for _, flag := range stringSlice(status["activeFlags"]) {
			if flag == "waitingOnApproval" {
				phase = PhaseWaitingApproval
			}
			if flag == "waitingOnUserInput" {
				phase = PhaseWaitingInput
			}
		}
	case "idle":
		phase = PhaseIdle
	case "systemError":
		phase = PhaseError
	case "notLoaded", "":
		return Event{}, false
	default:
		return Event{}, false
	}
	return Event{Schema: EventSchema, Provider: "codex", Profile: "codex", SessionID: threadID,
		Event: "thread/status/changed", Phase: phase, Source: source, OccurredAt: now,
		Routing: Routing{BundleID: "com.openai.codex"}}, true
}

func resolveCodexExecutable(environment map[string]string) string {
	for _, candidate := range []string{"/Applications/Codex.app/Contents/Resources/codex", filepath.Join(environment["HOME"], "Applications/Codex.app/Contents/Resources/codex")} {
		if candidate != "" {
			if info, err := os.Stat(candidate); err == nil && info.Mode()&0o111 != 0 {
				return candidate
			}
		}
	}
	pathEnvironment := environment["PATH"]
	if pathEnvironment == "" {
		pathEnvironment = os.Getenv("PATH")
	}
	for _, directory := range filepath.SplitList(pathEnvironment) {
		candidate := filepath.Join(directory, "codex")
		if info, err := os.Stat(candidate); err == nil && info.Mode()&0o111 != 0 {
			return candidate
		}
	}
	return ""
}

func rpcID(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case float64:
		return strconv.FormatInt(int64(typed), 10)
	case json.Number:
		return typed.String()
	default:
		return ""
	}
}

func objectSlice(value any) []map[string]any {
	raw, _ := value.([]any)
	result := make([]map[string]any, 0, len(raw))
	for _, item := range raw {
		if object, ok := item.(map[string]any); ok {
			result = append(result, object)
		}
	}
	return result
}

func stringSlice(value any) []string {
	raw, _ := value.([]any)
	result := make([]string, 0, len(raw))
	for _, item := range raw {
		if text, ok := item.(string); ok {
			result = append(result, text)
		}
	}
	return result
}
