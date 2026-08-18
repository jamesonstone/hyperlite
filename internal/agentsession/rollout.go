package agentsession

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"os"
	"strings"
	"time"
)

const maxRolloutTail = 2 * 1024 * 1024

func ReadRolloutTail(path string, limit int64) ([]byte, error) {
	if limit <= 0 || limit > maxRolloutTail {
		limit = maxRolloutTail
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer func() { _ = file.Close() }()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return nil, errors.New("rollout is not a regular file")
	}
	start := info.Size() - limit
	if start < 0 {
		start = 0
	}
	if _, err := file.Seek(start, io.SeekStart); err != nil {
		return nil, err
	}
	data, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err != nil || int64(len(data)) > limit {
		return nil, errors.New("rollout tail exceeds the safety limit")
	}
	if start > 0 {
		if newline := bytes.IndexByte(data, '\n'); newline >= 0 {
			data = data[newline+1:]
		} else {
			return []byte{}, nil
		}
	}
	return data, nil
}

func ParseCodexRolloutTail(data []byte, fallbackID string, now time.Time) (Event, error) {
	if len(data) > maxRolloutTail {
		return Event{}, errors.New("rollout tail exceeds the safety limit")
	}
	event := Event{Schema: EventSchema, Provider: "codex", Profile: "codex",
		SessionID: fallbackID, Event: "rollout", Phase: PhaseIdle,
		Source: SourceRollout, OccurredAt: now, Routing: Routing{BundleID: "com.openai.codex"}}
	messages := make([]Message, 0, maxMessages)
	runningTools := make(map[string]string)
	scanner := bufio.NewScanner(bytes.NewReader(data))
	scanner.Buffer(make([]byte, 64*1024), maxAppServerMessage)
	for scanner.Scan() {
		var row map[string]any
		if json.Unmarshal(scanner.Bytes(), &row) != nil {
			continue
		}
		if parsed := parseRolloutTime(firstString(row, "timestamp")); !parsed.IsZero() {
			event.OccurredAt = parsed
		}
		payload, _ := row["payload"].(map[string]any)
		switch firstString(row, "type") {
		case "session_meta":
			event.SessionID = firstNonempty(firstString(payload, "id"), event.SessionID)
			event.WorkspacePath = firstNonempty(firstString(payload, "cwd"), event.WorkspacePath)
			event.Title = firstNonempty(firstString(payload, "title"), event.Title)
			event.ParentID = firstNonempty(parentFromSource(payload["source"]), event.ParentID)
		case "turn_context":
			event.WorkspacePath = firstNonempty(firstString(payload, "cwd"), event.WorkspacePath)
		case "event_msg":
			parseCodexEventMessage(payload, &event, &messages, runningTools)
		case "response_item":
			parseCodexResponseItem(payload, &event, runningTools)
		}
	}
	if err := scanner.Err(); err != nil {
		return Event{}, err
	}
	if event.SessionID == "" {
		return Event{}, errors.New("rollout has no session identity")
	}
	event.Routing.WorkspacePath = event.WorkspacePath
	event.Messages = messages
	if len(runningTools) > 0 && !event.Phase.NeedsAttention() {
		event.Phase = PhaseProcessing
	}
	return event, nil
}

func parseCodexEventMessage(payload map[string]any, event *Event, messages *[]Message, running map[string]string) {
	switch firstString(payload, "type") {
	case "user_message":
		appendDisplayMessage(messages, "user", firstString(payload, "message"))
		event.Phase = PhaseProcessing
	case "agent_message":
		if firstString(payload, "phase") == "commentary" {
			return
		}
		text := firstString(payload, "message")
		appendDisplayMessage(messages, "assistant", text)
		event.LatestResult = text
	case "task_started":
		event.Phase = PhaseProcessing
	case "task_complete":
		if len(running) == 0 {
			event.Phase = PhaseCompleted
		}
	case "turn_aborted":
		event.Phase = PhaseIdle
		clear(running)
	}
}

func parseCodexResponseItem(payload map[string]any, event *Event, running map[string]string) {
	typeName := firstString(payload, "type")
	callID := firstString(payload, "call_id")
	switch typeName {
	case "function_call", "custom_tool_call":
		name := firstString(payload, "name")
		if callID != "" {
			running[callID] = name
		}
		if strings.Contains(strings.ToLower(name), "request_user_input") {
			event.Phase = PhaseWaitingInput
			event.ActionKind = "question"
			event.ActionTitle = "Input requested"
			event.ActionContext = "Open in Codex to answer"
			event.CompleteContext = false
		}
	case "function_call_output", "custom_tool_call_output":
		name := running[callID]
		delete(running, callID)
		if strings.Contains(strings.ToLower(name), "request_user_input") && len(running) == 0 {
			event.Phase = PhaseProcessing
			event.ActionKind = ""
			event.ActionTitle = ""
			event.ActionContext = ""
		}
	}
}

func appendDisplayMessage(messages *[]Message, role, text string) {
	text = BoundDisplayText(text, maxMessageRunes)
	if text == "" {
		return
	}
	*messages = append(*messages, Message{Role: role, Text: text})
	if len(*messages) > maxMessages {
		*messages = (*messages)[len(*messages)-maxMessages:]
	}
}

func parentFromSource(value any) string {
	source, _ := value.(map[string]any)
	subagent, _ := source["subagent"].(map[string]any)
	spawn, _ := subagent["thread_spawn"].(map[string]any)
	return firstString(spawn, "parent_thread_id")
}

func parseRolloutTime(value string) time.Time {
	parsed, _ := time.Parse(time.RFC3339Nano, value)
	return parsed
}
