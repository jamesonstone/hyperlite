package agentsession

import (
	"context"
	"time"
)

const maxCodexRolloutWatches = 32

type rolloutEntry struct {
	path       string
	identity   string
	seed       Event
	cursor     *RolloutCursor
	priority   int
	updatedAt  time.Time
	cancel     context.CancelFunc
	discovered bool
}

type RolloutRegistry struct {
	ctx     context.Context
	entries map[string]*rolloutEntry
	start   func(context.Context, string)
	changed func(int)
}

func NewRolloutRegistry(
	ctx context.Context,
	start func(context.Context, string),
	changed func(int),
) *RolloutRegistry {
	return &RolloutRegistry{ctx: ctx, entries: make(map[string]*rolloutEntry), start: start, changed: changed}
}

func (r *RolloutRegistry) Admit(path string, seed Event, discovered bool, now time.Time) (string, bool) {
	identity := ""
	if seed.Provider != "" && seed.SessionID != "" {
		identity = Identity(seed.Provider, seed.SessionID)
	}
	if existing, ok := r.entries[path]; ok {
		if identity == "" || existing.identity == "" || existing.identity == identity {
			existing.seed = mergeRolloutSeed(existing.seed, seed)
			existing.identity = firstNonempty(identity, existing.identity)
			existing.priority = rolloutPriority(existing.seed)
			existing.cursor.BindSeed(existing.seed)
			observed := nonzeroObservedTime(seed.OccurredAt, now)
			if observed.After(existing.updatedAt) {
				existing.updatedAt = observed
			}
			return "", false
		}
		r.remove(path)
	}
	evicted := ""
	if len(r.entries) >= maxCodexRolloutWatches {
		evicted = r.evictionCandidate()
		if evicted == "" {
			return "", false
		}
		candidate := r.entries[evicted]
		incomingPriority := rolloutPriority(seed)
		incomingTime := nonzeroObservedTime(seed.OccurredAt, now)
		if incomingPriority < candidate.priority ||
			(incomingPriority == candidate.priority && !incomingTime.After(candidate.updatedAt)) {
			return "", false
		}
		r.remove(evicted)
	}
	entryCtx, cancel := context.WithCancel(r.ctx)
	entry := &rolloutEntry{
		path: path, identity: identity, seed: seed, cursor: NewRolloutCursor(path, seed),
		priority: rolloutPriority(seed), updatedAt: nonzeroObservedTime(seed.OccurredAt, now),
		cancel: cancel, discovered: discovered,
	}
	r.entries[path] = entry
	if r.start != nil {
		r.start(entryCtx, path)
	}
	r.notify()
	return evicted, true
}

func (r *RolloutRegistry) Remove(path string) bool {
	if _, ok := r.entries[path]; !ok {
		return false
	}
	r.remove(path)
	return true
}

func (r *RolloutRegistry) ReleaseIdentity(identity string) int {
	removed := 0
	for path, entry := range r.entries {
		if entry.identity == identity {
			r.remove(path)
			removed++
		}
	}
	return removed
}

func (r *RolloutRegistry) Update(path string, event Event, now time.Time) {
	entry, ok := r.entries[path]
	if !ok {
		return
	}
	if event.Provider != "" && event.SessionID != "" {
		entry.identity = Identity(event.Provider, event.SessionID)
	}
	entry.seed = mergeRolloutSeed(entry.seed, event)
	entry.cursor.BindSeed(entry.seed)
	entry.priority = rolloutPriority(event)
	entry.updatedAt = nonzeroObservedTime(event.OccurredAt, now)
}

func (r *RolloutRegistry) Entry(path string) (*rolloutEntry, bool) {
	entry, ok := r.entries[path]
	return entry, ok
}

func (r *RolloutRegistry) Len() int { return len(r.entries) }

func (r *RolloutRegistry) Close() {
	for path := range r.entries {
		r.remove(path)
	}
}

func (r *RolloutRegistry) remove(path string) {
	entry, ok := r.entries[path]
	if !ok {
		return
	}
	entry.cancel()
	delete(r.entries, path)
	r.notify()
}

func (r *RolloutRegistry) evictionCandidate() string {
	var candidate *rolloutEntry
	for _, entry := range r.entries {
		if entry.priority == 4 {
			continue
		}
		if candidate == nil || entry.priority < candidate.priority ||
			(entry.priority == candidate.priority && entry.updatedAt.Before(candidate.updatedAt)) {
			candidate = entry
		}
	}
	if candidate == nil {
		return ""
	}
	return candidate.path
}

func (r *RolloutRegistry) notify() {
	if r.changed != nil {
		r.changed(len(r.entries))
	}
}

func rolloutPriority(event Event) int {
	if event.Phase.NeedsAttention() || safeAction(event) != nil {
		return 4
	}
	if event.Phase.Active() || event.ActiveTool {
		return 3
	}
	if event.Phase == PhaseIdle || event.Phase == PhaseStarting || event.Phase == "" {
		return 2
	}
	return 1
}

func mergeRolloutSeed(current, incoming Event) Event {
	current.Provider = firstNonempty(incoming.Provider, current.Provider, "codex")
	current.Profile = firstNonempty(incoming.Profile, current.Profile, "codex")
	current.SessionID = firstNonempty(incoming.SessionID, current.SessionID)
	current.ParentID = firstNonempty(incoming.ParentID, current.ParentID)
	current.Title = firstNonempty(incoming.Title, current.Title)
	current.WorkspacePath = firstNonempty(incoming.WorkspacePath, current.WorkspacePath)
	current.Routing = mergeRouting(current.Routing, incoming.Routing, current.WorkspacePath)
	if incoming.Phase != "" {
		current.Phase = incoming.Phase
	}
	if !incoming.OccurredAt.IsZero() {
		current.OccurredAt = incoming.OccurredAt
	}
	current.AuxiliaryKind = firstNonempty(incoming.AuxiliaryKind, current.AuxiliaryKind)
	current.HasPrompt = current.HasPrompt || incoming.HasPrompt
	return current
}

func nonzeroObservedTime(value, fallback time.Time) time.Time {
	if value.IsZero() {
		return fallback
	}
	return value
}
