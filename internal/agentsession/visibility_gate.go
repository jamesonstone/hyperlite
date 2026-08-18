package agentsession

import (
	"sort"
	"strings"
	"time"
)

const blankSessionGrace = 2 * time.Second

type pendingVisibility struct {
	event    Event
	deadline time.Time
}

type VisibilityGate struct {
	pending map[string]pendingVisibility
}

func NewVisibilityGate() *VisibilityGate {
	return &VisibilityGate{pending: make(map[string]pendingVisibility)}
}

func (g *VisibilityGate) Offer(event Event, exists bool, now time.Time) (Event, bool, bool) {
	id := Identity(event.Provider, event.SessionID)
	if explicitlyAuxiliary(event) {
		delete(g.pending, id)
		return Event{}, false, true
	}
	if event.visibilityReleased {
		delete(g.pending, id)
		return event, true, false
	}
	if exists || materialSessionEvidence(event) || !blankPlaceholder(event) {
		delete(g.pending, id)
		return event, true, false
	}
	if len(g.pending) >= maxSessions {
		return Event{}, false, true
	}
	g.pending[id] = pendingVisibility{event: event, deadline: now.Add(blankSessionGrace)}
	return Event{}, false, false
}

func (g *VisibilityGate) Due(now time.Time) (events []Event, filtered int) {
	ids := make([]string, 0, len(g.pending))
	for id := range g.pending {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		pending := g.pending[id]
		if pending.deadline.After(now) {
			continue
		}
		delete(g.pending, id)
		if corroboratedBlankPlaceholder(pending.event) {
			filtered++
			continue
		}
		pending.event.visibilityReleased = true
		events = append(events, pending.event)
	}
	return events, filtered
}

func (g *VisibilityGate) NextDeadline() (time.Time, bool) {
	var next time.Time
	for _, pending := range g.pending {
		if next.IsZero() || pending.deadline.Before(next) {
			next = pending.deadline
		}
	}
	return next, !next.IsZero()
}

func (g *VisibilityGate) Remove(identity string) { delete(g.pending, identity) }

func explicitlyAuxiliary(event Event) bool {
	kind := strings.ToLower(strings.TrimSpace(event.AuxiliaryKind))
	return kind != "" && (strings.Contains(kind, "compact") ||
		strings.Contains(kind, "title") || strings.Contains(kind, "maintenance"))
}

func materialSessionEvidence(event Event) bool {
	return event.Synthetic || event.HasPrompt || event.ActiveTool || event.RequestID != "" ||
		event.ActionKind != "" || event.Message != "" || len(event.Messages) > 0 ||
		event.LatestResult != "" || (event.Source == SourceRollout && event.RolloutPath != "")
}

func blankPlaceholder(event Event) bool {
	return strings.TrimSpace(event.Title) == "" && !materialSessionEvidence(event) &&
		(event.Phase == "" || event.Phase == PhaseStarting || event.Phase == PhaseIdle)
}

func corroboratedBlankPlaceholder(event Event) bool {
	if !blankPlaceholder(event) {
		return false
	}
	signals := 0
	if event.Source == SourceAppServer || event.Source == SourceRollout {
		signals++
	}
	if event.WorkspacePath == "" && event.ParentID == "" {
		signals++
	}
	if event.Phase == "" || event.Phase == PhaseStarting || event.Phase == PhaseIdle {
		signals++
	}
	return signals >= 3
}
