package agentsession

import "time"

func codexRolloutDiscoveryEvent(thread, status map[string]any, now time.Time) (Event, bool) {
	if firstString(status, "type") != "notLoaded" {
		return Event{}, false
	}
	threadID := firstString(thread, "id", "threadId")
	path := firstString(thread, "rolloutPath", "sessionFilePath", "path")
	if threadID == "" || path == "" {
		return Event{}, false
	}
	workspace := firstString(thread, "cwd")
	observedAt := firstTime(thread, "updatedAt", "updated_at", "createdAt", "created_at")
	if observedAt.IsZero() {
		observedAt = now
	}
	return Event{
		Schema: EventSchema, Provider: "codex", Profile: "codex",
		SessionID: threadID, ParentID: firstString(thread, "parentThreadId", "parent_thread_id", "forkedFromId"),
		Event: "rollout/discovered", Source: SourceAppServer, OccurredAt: observedAt,
		WorkspacePath: workspace, Title: firstString(thread, "name"), RolloutPath: path,
		Routing:     Routing{BundleID: "com.openai.codex", WorkspacePath: workspace},
		rolloutHint: true,
	}, true
}
