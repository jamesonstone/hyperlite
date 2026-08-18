package agentsession

import (
	"encoding/json"
	"time"
)

func (c *RolloutCursor) consume(data []byte, now time.Time, rowBudget int) (int, int) {
	rows := 0
	for index, value := range data {
		if c.discarding {
			if value == '\n' {
				c.discarding = false
				rows++
				if rows >= rowBudget {
					return index + 1, rows
				}
			}
			continue
		}
		if value == '\n' {
			c.consumeLine(c.partial, now)
			if cap(c.partial) > rolloutChunkBytes {
				c.partial = nil
			} else {
				c.partial = c.partial[:0]
			}
			rows++
			if rows >= rowBudget {
				return index + 1, rows
			}
			continue
		}
		if len(c.partial) >= maxRolloutRecord {
			c.partial = nil
			c.discarding = true
			continue
		}
		c.partial = append(c.partial, value)
	}
	return len(data), rows
}

func (c *RolloutCursor) consumeLine(line []byte, now time.Time) {
	if len(line) == 0 || len(line) > maxRolloutRecord {
		return
	}
	var row map[string]any
	if json.Unmarshal(line, &row) != nil {
		return
	}
	if parsed := parseRolloutTime(firstString(row, "timestamp")); !parsed.IsZero() {
		c.projection.OccurredAt = parsed
	} else if c.projection.OccurredAt.IsZero() {
		c.projection.OccurredAt = now
	}
	payload, _ := row["payload"].(map[string]any)
	switch firstString(row, "type") {
	case "session_meta":
		c.projection.SessionID = firstNonempty(firstString(payload, "id"), c.projection.SessionID)
		c.projection.WorkspacePath = firstNonempty(firstString(payload, "cwd"), c.projection.WorkspacePath)
		c.projection.Title = firstNonempty(firstString(payload, "title"), c.projection.Title)
		c.projection.ParentID = firstNonempty(parentFromSource(payload["source"]), c.projection.ParentID)
		c.projection.AuxiliaryKind = auxiliaryKindFromSource(payload["source"])
	case "turn_context":
		c.projection.WorkspacePath = firstNonempty(firstString(payload, "cwd"), c.projection.WorkspacePath)
	case "event_msg":
		if firstString(payload, "type") == "user_message" {
			c.projection.HasPrompt = true
		}
		parseCodexEventMessage(payload, &c.projection, &c.messages, c.running)
	case "response_item":
		parseCodexResponseItem(payload, &c.projection, c.running)
	}
}

func (c *RolloutCursor) finalizeProjection(now time.Time) {
	if c.projection.OccurredAt.IsZero() {
		c.projection.OccurredAt = now
	}
	c.projection.Routing.WorkspacePath = c.projection.WorkspacePath
	c.projection.Messages = append([]Message{}, c.messages...)
	c.projection.ActiveTool = len(c.running) > 0
	if c.projection.ActiveTool && !c.projection.Phase.NeedsAttention() {
		c.projection.Phase = PhaseProcessing
	}
	c.projection = mustReconcileRolloutSeed(c.projection, c.seed)
}

func cloneRolloutEvent(value Event) Event {
	value.Messages = append([]Message{}, value.Messages...)
	return value
}

func mustReconcileRolloutSeed(event, seed Event) Event {
	event.ParentID = firstNonempty(event.ParentID, seed.ParentID)
	event.Title = firstNonempty(event.Title, seed.Title)
	event.WorkspacePath = firstNonempty(event.WorkspacePath, seed.WorkspacePath)
	event.Routing = mergeRouting(seed.Routing, event.Routing, event.WorkspacePath)
	event.AuxiliaryKind = firstNonempty(event.AuxiliaryKind, seed.AuxiliaryKind)
	event.HasPrompt = event.HasPrompt || seed.HasPrompt
	return event
}

func auxiliaryKindFromSource(value any) string {
	source, _ := value.(map[string]any)
	for _, key := range []string{"subAgentCompact", "sub_agent_compact", "titleGeneration", "title_generation", "maintenance"} {
		if _, ok := source[key]; ok {
			return key
		}
	}
	return ""
}
