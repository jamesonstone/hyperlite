package agentsession

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
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
		return codexRolloutDiscoveryEvent(thread, status, now)
	}
	event.Title = firstString(thread, "name")
	event.WorkspacePath = firstString(thread, "cwd")
	event.ParentID = firstString(thread, "parentThreadId", "parent_thread_id", "forkedFromId")
	event.RolloutPath = firstString(thread, "rolloutPath", "sessionFilePath", "path")
	event.AuxiliaryKind = codexAuxiliaryKind(thread)
	event.HasPrompt = firstBool(thread, "hasUserMessage", "has_user_message", "hasPrompt")
	event.Routing = Routing{BundleID: "com.openai.codex", WorkspacePath: event.WorkspacePath}
	return event, true
}

func codexStatusEvent(threadID string, status map[string]any, now time.Time) (Event, bool) {
	if threadID == "" {
		return Event{}, false
	}
	typeName := firstString(status, "type")
	var phase Phase
	const source = SourceAppServer
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

func mergeEnvironment(base []string, overrides map[string]string) []string {
	values := make(map[string]string, len(base)+len(overrides))
	for _, entry := range base {
		key, value, ok := strings.Cut(entry, "=")
		if ok && key != "" {
			values[key] = value
		}
	}
	for key, value := range overrides {
		if key != "" {
			values[key] = value
		}
	}
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	result := make([]string, 0, len(keys))
	for _, key := range keys {
		result = append(result, key+"="+values[key])
	}
	return result
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
