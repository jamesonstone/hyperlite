package agentsession

import (
	"path/filepath"
	"strings"
	"unicode/utf8"
)

func phaseForEvent(name string) Phase {
	switch strings.ToLower(name) {
	case "sessionstart", "session_start", "started":
		return PhaseStarting
	case "permissionrequest", "approval", "waiting_for_approval":
		return PhaseWaitingApproval
	case "askuserquestion", "question", "waiting_for_input":
		return PhaseWaitingInput
	case "stop", "task_complete", "completed":
		return PhaseCompleted
	case "sessionend", "session_end", "ended":
		return PhaseEnded
	case "error", "erroroccurred", "failed":
		return PhaseError
	case "idle":
		return PhaseIdle
	default:
		return PhaseProcessing
	}
}

func displayRole(role string) string {
	switch strings.ToLower(strings.TrimSpace(role)) {
	case "user":
		return "user"
	case "assistant", "agent":
		return "assistant"
	default:
		return ""
	}
}

func projectName(workspace, fallback string) string {
	if workspace == "" || workspace == "/" {
		return fallback
	}
	name := filepath.Base(filepath.Clean(workspace))
	if name == "." || name == string(filepath.Separator) || name == "" {
		return fallback
	}
	return name
}

func mergeRouting(current, incoming Routing, workspace string) Routing {
	current.BundleID = firstNonempty(incoming.BundleID, current.BundleID)
	current.Terminal = firstNonempty(incoming.Terminal, current.Terminal)
	current.TerminalID = firstNonempty(incoming.TerminalID, current.TerminalID)
	current.TmuxSession = firstNonempty(incoming.TmuxSession, current.TmuxSession)
	current.TmuxPane = firstNonempty(incoming.TmuxPane, current.TmuxPane)
	current.WorkspacePath = firstNonempty(workspace, incoming.WorkspacePath, current.WorkspacePath)
	return current
}

func routingAvailable(value Routing) bool {
	return value.BundleID != "" || value.Terminal != "" || value.WorkspacePath != ""
}

func actionAllowed(action PendingAction, requested string) bool {
	switch requested {
	case "allow_once":
		return action.CanAllowOnce
	case "deny":
		return action.CanDeny
	case "answer":
		return action.CanAnswer
	default:
		return false
	}
}

func validAnswers(answers map[string][]string) bool {
	if len(answers) == 0 {
		return false
	}
	total := 0
	for key, values := range answers {
		if strings.TrimSpace(key) == "" || len(values) == 0 {
			return false
		}
		for _, value := range values {
			if strings.TrimSpace(value) == "" {
				return false
			}
			total += utf8.RuneCountInString(value)
			if total > maxActionRunes {
				return false
			}
		}
	}
	return true
}

func cloneSession(value Session) Session {
	value.Messages = append([]Message{}, value.Messages...)
	if value.Action != nil {
		copyAction := *value.Action
		copyAction.Arguments = make(map[string]string, len(value.Action.Arguments))
		for key, item := range value.Action.Arguments {
			copyAction.Arguments[key] = item
		}
		value.Action = &copyAction
	}
	return value
}

func firstNonempty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
