package agentsession

import (
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// MaxHookPayload is the largest provider hook envelope Hyperlite accepts.
const MaxHookPayload = 1024 * 1024

func NormalizeHook(profile Profile, raw []byte, environment map[string]string, now time.Time) (Event, error) {
	if len(raw) == 0 || len(raw) > MaxHookPayload {
		return Event{}, errors.New("hook payload is empty or exceeds the safety limit")
	}
	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		return Event{}, errors.New("hook payload is malformed")
	}
	eventName := firstString(payload, "hook_event_name", "event", "event_name", "type", "hookEventName")
	sessionID := firstString(payload, "session_id", "sessionId", "thread_id", "threadId", "conversation_id", "conversationId")
	if sessionID == "" {
		return Event{}, errors.New("hook payload has no stable session identifier")
	}
	workspace := firstString(payload, "cwd", "workspace", "workspace_path", "workspacePath")
	if workspace == "" {
		workspace = environment["PWD"]
	}
	toolInput := firstObject(payload, "tool_input", "toolInput", "input", "arguments")
	requestID := firstString(payload, "tool_use_id", "toolUseId", "request_id", "requestId", "call_id", "callId")
	message, role := displayMessage(payload, eventName)
	actionKind := actionKindFor(eventName, payload)
	context := decisionContext(payload, toolInput)
	expectsResponse := actionKind != "" && requestID != "" && profile.ActionMode == actionModeBlocking
	arguments, complete := SanitizeArguments(toolInput)
	argumentValues := make(map[string]any, len(arguments))
	for key, value := range arguments {
		argumentValues[key] = value
	}
	processID := firstInt(payload, "process_id", "processId", "pid")
	processStart := firstString(payload, "process_start_token", "processStartToken", "process_start")
	lowerEvent := strings.ToLower(eventName)
	return Event{
		Schema: EventSchema, Provider: profile.Provider, Profile: profile.ID,
		SessionID: sessionID, ParentID: firstString(payload, "parent_session_id", "parentThreadId", "parent_thread_id"),
		Event: eventName, Phase: phaseForPayload(eventName, payload), Source: SourceHook,
		OccurredAt: now, WorkspacePath: workspace,
		Title:       firstString(payload, "session_name", "name", "title"),
		MessageRole: role, Message: message,
		LatestResult: finalResult(payload, eventName), RequestID: requestID,
		ActionKind: actionKind, ActionTitle: actionTitle(actionKind, payload),
		ActionContext: context, Arguments: argumentValues,
		CompleteContext: complete && context != "", ExpectsResponse: expectsResponse,
		Routing:       routingFrom(payload, environment, workspace),
		RolloutPath:   firstString(payload, "rollout_path", "session_file_path", "transcript_path"),
		AuxiliaryKind: firstString(payload, "auxiliary_kind", "auxiliaryKind", "session_kind", "sessionKind"),
		HasPrompt:     strings.Contains(lowerEvent, "userprompt") || strings.Contains(lowerEvent, "user_message"),
		ActiveTool:    strings.Contains(lowerEvent, "pretool") || strings.Contains(lowerEvent, "tool_start"),
		ProcessID:     processID, ProcessStart: processStart,
	}, nil
}

func phaseForPayload(eventName string, payload map[string]any) Phase {
	status := strings.ToLower(firstString(payload, "status", "phase"))
	switch status {
	case "waiting_for_approval", "approval":
		return PhaseWaitingApproval
	case "waiting_for_input", "question":
		return PhaseWaitingInput
	case "processing", "running", "running_tool", "active":
		return PhaseProcessing
	case "completed", "complete":
		return PhaseCompleted
	case "failed", "error":
		return PhaseError
	case "ended":
		return PhaseEnded
	}
	return phaseForEvent(eventName)
}

func displayMessage(payload map[string]any, eventName string) (string, string) {
	lower := strings.ToLower(eventName)
	if strings.Contains(lower, "reason") || strings.Contains(lower, "thinking") || strings.Contains(lower, "commentary") {
		return "", ""
	}
	if strings.Contains(lower, "userprompt") || strings.Contains(lower, "user_message") {
		return firstString(payload, "prompt", "message", "text"), "user"
	}
	if strings.Contains(lower, "agentmessage") || strings.Contains(lower, "assistant") {
		return firstString(payload, "message", "text", "result"), "assistant"
	}
	return "", ""
}

func actionKindFor(eventName string, payload map[string]any) string {
	lower := strings.ToLower(eventName)
	tool := strings.ToLower(firstString(payload, "tool_name", "toolName", "tool"))
	if strings.Contains(lower, "permission") || strings.Contains(lower, "approval") {
		return "approval"
	}
	if strings.Contains(lower, "question") || strings.Contains(tool, "askuserquestion") || strings.Contains(tool, "ask_followup_question") {
		return "question"
	}
	return ""
}

func actionTitle(kind string, payload map[string]any) string {
	if title := firstString(payload, "action_title", "title"); title != "" {
		return title
	}
	tool := firstString(payload, "tool_name", "toolName", "tool")
	if kind == "question" {
		return "Input requested"
	}
	if tool != "" {
		return "Allow " + tool + "?"
	}
	if kind == "approval" {
		return "Approval requested"
	}
	return ""
}

func decisionContext(payload, toolInput map[string]any) string {
	if value := firstString(payload, "question", "action_context", "permission", "message"); value != "" {
		return BoundDisplayText(value, maxActionRunes)
	}
	for _, key := range []string{"command", "cmd", "path", "file_path", "domain", "url", "permissions"} {
		if value, ok := toolInput[key]; ok {
			return BoundDisplayText(fmt.Sprint(value), maxActionRunes)
		}
	}
	return ""
}

func finalResult(payload map[string]any, eventName string) string {
	lower := strings.ToLower(eventName)
	if !strings.Contains(lower, "stop") && !strings.Contains(lower, "complete") && !strings.Contains(lower, "end") {
		return ""
	}
	return firstString(payload, "last_assistant_message", "result", "message")
}

func routingFrom(payload map[string]any, environment map[string]string, workspace string) Routing {
	return Routing{
		BundleID:      firstNonempty(firstString(payload, "bundle_id", "bundleIdentifier"), environment["__CFBundleIdentifier"]),
		Terminal:      firstNonempty(firstString(payload, "terminal", "terminal_program"), environment["TERM_PROGRAM"]),
		TerminalID:    firstNonempty(firstString(payload, "terminal_id", "terminalSessionId"), environment["TERM_SESSION_ID"], environment["ITERM_SESSION_ID"]),
		TmuxSession:   firstNonempty(firstString(payload, "tmux_session"), environment["TMUX"]),
		TmuxPane:      firstNonempty(firstString(payload, "tmux_pane"), environment["TMUX_PANE"]),
		WorkspacePath: workspace,
	}
}

func firstString(values map[string]any, keys ...string) string {
	for _, key := range keys {
		if value, ok := values[key]; ok {
			switch typed := value.(type) {
			case string:
				if strings.TrimSpace(typed) != "" {
					return strings.TrimSpace(typed)
				}
			case json.Number:
				return typed.String()
			case float64:
				return fmt.Sprintf("%.0f", typed)
			}
		}
	}
	return ""
}

func firstObject(values map[string]any, keys ...string) map[string]any {
	for _, key := range keys {
		if value, ok := values[key].(map[string]any); ok {
			return value
		}
	}
	return map[string]any{}
}

func firstInt(values map[string]any, keys ...string) int {
	text := firstString(values, keys...)
	value, err := strconv.Atoi(text)
	if err != nil || value <= 1 {
		return 0
	}
	return value
}

func BridgeExecutable(appBundle string) string {
	if appBundle == "" {
		return "hyperlite"
	}
	return filepath.Join(appBundle, "Contents", "MacOS", "hyperlite-cli")
}
