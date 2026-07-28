package threadstate

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func Reconcile(state *State, threads []model.Thread, now time.Time) []model.Thread {
	return ReconcileSelected(state, threads, repositoriesIn(threads), now)
}

func ReconcileSelected(
	state *State,
	threads []model.Thread,
	selectedRepositories []string,
	now time.Time,
) []model.Thread {
	records := make(map[string]ThreadRecord, len(state.Threads))
	aliases := make(map[string]string)
	selected := make(map[string]struct{}, len(selectedRepositories))
	for _, repository := range selectedRepositories {
		selected[repository] = struct{}{}
	}
	for _, record := range state.Threads {
		records[record.ID] = record
		aliases[record.ID] = record.ID
		for _, alias := range record.Aliases {
			aliases[alias] = record.ID
		}
	}
	updated := make(map[string]ThreadRecord, len(threads))
	consumed := make(map[string]bool, len(threads))
	reconciled := make([]model.Thread, 0, len(threads))
	for index := range threads {
		thread := &threads[index]
		record, found := matchingRecord(*thread, records, aliases)
		signature := signatureFor(*thread)
		revision := digest(signature)
		if !found {
			record = ThreadRecord{
				ID: thread.ID, Aliases: append([]string{}, thread.Aliases...),
				Revision: revision, Signature: signature,
				Moments: []model.AttentionMoment{}, UpdatedAt: now,
			}
			if candidate := currentCandidate(*thread); candidate != nil {
				record.Moments = append(record.Moments, moment(*thread, revision, *candidate, now))
			}
		} else {
			oldID := record.ID
			consumed[oldID] = true
			record.ID = thread.ID
			record.Aliases = mergeStrings(record.Aliases, thread.Aliases, []string{oldID})
			wasMissing := record.Missing
			record.Missing = false
			if record.Revision != revision {
				if candidate := changedCandidate(record.Signature, signature, *thread); (!wasMissing || record.Signature != signature) && candidate != nil {
					record.Moments = append(record.Moments, moment(*thread, revision, *candidate, now))
				}
				record.Revision = revision
				record.Signature = signature
				record.UpdatedAt = now
			}
		}
		if len(record.Moments) > 20 {
			record.Moments = append([]model.AttentionMoment{}, record.Moments[len(record.Moments)-20:]...)
		}
		thread.Note = record.Note
		thread.Attention = append([]model.AttentionMoment{}, record.Moments...)
		thread.LatestMaterialRevision = record.Revision
		thread.WhyNow = whyNow(*thread)
		record.Snapshot = snapshotFor(*thread)
		if shouldRetainCurrentSnapshot(record.Snapshot, now) {
			updated[record.ID] = record
			reconciled = append(reconciled, *thread)
		}
	}
	for _, record := range state.Threads {
		if _, exists := updated[record.ID]; exists || consumed[record.ID] {
			continue
		}
		if shouldRetainSnapshot(record.Snapshot, selected, now) {
			thread := staleSnapshot(record.Snapshot)
			if thread.Active && !record.Missing {
				record.Missing = true
				record.Revision = digest(struct {
					Signature MaterialSignature `json:"signature"`
					Missing   bool              `json:"missing"`
				}{record.Signature, true})
				record.Moments = append(record.Moments, moment(thread, record.Revision, candidate{
					kind:     model.AttentionUncertain,
					summary:  "Previously active evidence disappeared before canonical closure",
					why:      "Artifact disappearance cannot establish goal completion.",
					evidence: evidenceIDs(thread.Evidence),
				}, now))
				record.UpdatedAt = now
			}
			if len(record.Moments) > 20 {
				record.Moments = append([]model.AttentionMoment{}, record.Moments[len(record.Moments)-20:]...)
			}
			thread.Note = record.Note
			thread.Attention = append([]model.AttentionMoment{}, record.Moments...)
			thread.LatestMaterialRevision = record.Revision
			thread.WhyNow = whyNow(thread)
			record.Snapshot = snapshotFor(thread)
			reconciled = append(reconciled, thread)
			updated[record.ID] = record
		}
	}
	state.Threads = state.Threads[:0]
	for _, record := range updated {
		state.Threads = append(state.Threads, record)
	}
	sort.Slice(state.Threads, func(i, j int) bool { return state.Threads[i].ID < state.Threads[j].ID })
	retainCurrentInferences(state)
	return reconciled
}

func retainCurrentInferences(state *State) {
	current := make(map[string]struct{}, len(state.Threads))
	for _, record := range state.Threads {
		current[record.ID] = struct{}{}
	}
	filtered := state.Inferences[:0]
	for _, record := range state.Inferences {
		if _, exists := current[record.ThreadID]; exists {
			filtered = append(filtered, record)
		}
	}
	state.Inferences = filtered
}

func repositoriesIn(threads []model.Thread) []string {
	var repositories []string
	for _, thread := range threads {
		repositories = append(repositories, thread.Repositories...)
	}
	return uniqueStrings(repositories)
}

func shouldRetainSnapshot(snapshot model.Thread, selected map[string]struct{}, now time.Time) bool {
	if snapshot.ID == "" {
		return false
	}
	inScope := false
	for _, repository := range snapshot.Repositories {
		if _, exists := selected[repository]; exists {
			inScope = true
			break
		}
	}
	if !inScope {
		return false
	}
	return snapshot.Active || recentSnapshot(snapshot.UpdatedAt, now)
}

func shouldRetainCurrentSnapshot(snapshot model.Thread, now time.Time) bool {
	if snapshot.ID == "" {
		return false
	}
	return snapshot.Active || recentSnapshot(snapshot.UpdatedAt, now)
}

func recentSnapshot(updatedAt, now time.Time) bool {
	return !updatedAt.IsZero() && !updatedAt.After(now) && now.Sub(updatedAt) <= 30*24*time.Hour
}

func staleSnapshot(snapshot model.Thread) model.Thread {
	thread := snapshot
	thread.Artifacts = append([]model.ThreadArtifact{}, snapshot.Artifacts...)
	for index := range thread.Artifacts {
		thread.Artifacts[index].Freshness = "stale"
	}
	thread.Evidence = append([]model.EvidenceRef{}, snapshot.Evidence...)
	for index := range thread.Evidence {
		thread.Evidence[index].Freshness = "stale"
	}
	return thread
}

func snapshotFor(thread model.Thread) model.Thread {
	thread.Attention = nil
	thread.Note = ""
	thread.WhyNow = ""
	thread.LatestMaterialRevision = ""
	return thread
}

func MarkSeen(state *State, id, revision string) error {
	index := findRecord(state, id)
	if index < 0 {
		return fmt.Errorf("unknown thread %q", id)
	}
	record := &state.Threads[index]
	if record.Revision != revision {
		return fmt.Errorf("thread %q advanced; refresh before marking it seen", id)
	}
	for index := range record.Moments {
		record.Moments[index].Seen = true
	}
	record.SeenRevision = revision
	return nil
}

func SetNote(state *State, id, note string) error {
	index := findRecord(state, id)
	if index < 0 {
		return fmt.Errorf("unknown thread %q", id)
	}
	state.Threads[index].Note = strings.TrimSpace(note)
	return nil
}

func CachedInference(state State, threadID, digest string) (model.InferenceThread, bool) {
	for _, record := range state.Inferences {
		if record.ThreadID == threadID && record.Digest == digest {
			return record.Inference, true
		}
	}
	return model.InferenceThread{}, false
}

func SetInference(state *State, threadID, evidenceDigest string, value model.InferenceThread, now time.Time) {
	for index := range state.Inferences {
		if state.Inferences[index].ThreadID == threadID {
			state.Inferences[index] = InferenceRecord{
				ThreadID: threadID, Digest: evidenceDigest, Inference: value, UpdatedAt: now,
			}
			return
		}
	}
	state.Inferences = append(state.Inferences, InferenceRecord{
		ThreadID: threadID, Digest: evidenceDigest, Inference: value, UpdatedAt: now,
	})
}

func EvidenceDigest(thread model.Thread) string {
	return digest(struct {
		ID       string
		Evidence []model.EvidenceRef
	}{thread.ID, thread.Evidence})
}

func matchingRecord(thread model.Thread, records map[string]ThreadRecord, aliases map[string]string) (ThreadRecord, bool) {
	candidates := append([]string{thread.ID}, thread.Aliases...)
	for _, candidate := range candidates {
		if id, exists := aliases[candidate]; exists {
			record, found := records[id]
			return record, found
		}
	}
	return ThreadRecord{}, false
}

func findRecord(state *State, id string) int {
	for index, record := range state.Threads {
		if record.ID == id {
			return index
		}
		for _, alias := range record.Aliases {
			if alias == id {
				return index
			}
		}
	}
	return -1
}
