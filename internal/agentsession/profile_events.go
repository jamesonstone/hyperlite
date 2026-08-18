package agentsession

var profileEvents = map[string][]string{
	"claude-code":   {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "SessionEnd", "PreCompact"},
	"codex":         {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"},
	"gemini":        {"SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "BeforeTool", "AfterTool", "Notification", "PreCompress"},
	"antigravity":   {"PreToolUse", "PostToolUse", "PreInvocation", "PostInvocation", "Stop"},
	"hermes":        {"session_start", "user_prompt", "tool_start", "tool_end", "assistant_reply", "session_end"},
	"pi":            {"session_start", "user_prompt", "tool_start", "tool_end", "assistant_reply", "session_end"},
	"qwen-code":     {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "SessionEnd", "PreCompact"},
	"kimi":          {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"},
	"openclaw":      {"session_start", "message_received", "tool_start", "tool_end", "message_sent", "session_end"},
	"opencode":      {"session.created", "message.updated", "tool.execute.before", "tool.execute.after", "session.idle", "session.error"},
	"cursor":        {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"},
	"qoder":         {"UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop"},
	"qoder-cli":     {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "SessionEnd", "PreCompact"},
	"qoder-cn":      {"UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop"},
	"qoder-cn-cli":  {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "SessionEnd", "PreCompact"},
	"qoderwork":     {"UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop"},
	"codebuddy":     {"UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop"},
	"codebuddy-cli": {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "SessionEnd"},
	"workbuddy":     {"UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop"},
	"copilot":       {"sessionStart", "sessionEnd", "userPromptSubmitted", "preToolUse", "postToolUse", "agentStop", "subagentStop", "errorOccurred"},
}

func EventsForProfile(id string) []string {
	values := profileEvents[id]
	result := make([]string, len(values))
	copy(result, values)
	return result
}
