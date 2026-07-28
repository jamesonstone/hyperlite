package threadstate

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
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
		updated[record.ID] = record
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
			threads = append(threads, thread)
		}
		updated[record.ID] = record
	}
	state.Threads = state.Threads[:0]
	for _, record := range updated {
		state.Threads = append(state.Threads, record)
	}
	sort.Slice(state.Threads, func(i, j int) bool { return state.Threads[i].ID < state.Threads[j].ID })
	return threads
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

func signatureFor(thread model.Thread) MaterialSignature {
	return MaterialSignature{
		Goal: strings.TrimSpace(thread.Goal), Rationale: strings.TrimSpace(thread.Rationale),
		Phase: thread.Phase, Dependencies: digest(thread.Dependencies),
		Implications: digest(thread.Implications), Obligations: digest(thread.Obligations),
		Review: reviewSignature(thread),
	}
}

func reviewSignature(thread model.Thread) string {
	var values []string
	for _, implication := range thread.Implications {
		if implication.Category == "review_decision" {
			values = append(values, implication.Summary)
		}
	}
	sort.Strings(values)
	return strings.Join(values, "\n")
}

type candidate struct {
	kind     model.AttentionKind
	summary  string
	why      string
	evidence []string
}

func currentCandidate(thread model.Thread) *candidate {
	for _, implication := range thread.Implications {
		if implication.Category == "review_decision" {
			return &candidate{
				kind: model.AttentionDecide, summary: implication.Summary,
				why:      "Review evidence challenges a material direction or boundary.",
				evidence: implication.EvidenceIDs,
			}
		}
	}
	if hasMergedArtifact(thread) && hasOpenObligation(thread) {
		return &candidate{
			kind: model.AttentionReconcile, summary: "Implementation advanced, but operational obligations remain",
			why:      "Artifact completion does not complete the larger goal.",
			evidence: obligationEvidence(thread),
		}
	}
	if thread.Phase == model.ThreadReviewing && hasBoundaryImplication(thread) {
		return &candidate{
			kind: model.AttentionGuard, summary: "A consequential change is approaching a delivery boundary",
			why:      "Production, security, migration, or infrastructure implications should be understood before merge.",
			evidence: implicationEvidence(thread),
		}
	}
	if hasStaleEvidence(thread) {
		return &candidate{
			kind: model.AttentionUncertain, summary: "Thread conclusions rely on incomplete or stale evidence",
			why:      "Hyperlite cannot safely infer the current coordination state.",
			evidence: evidenceIDs(thread.Evidence),
		}
	}
	return nil
}

func changedCandidate(previous, current MaterialSignature, thread model.Thread) *candidate {
	if candidate := currentCandidate(thread); candidate != nil {
		return candidate
	}
	switch {
	case previous.Dependencies != current.Dependencies || previous.Obligations != current.Obligations:
		return &candidate{
			kind: model.AttentionReconcile, summary: "Dependencies or remaining obligations changed",
			why:      "The coordination path for this goal is materially different.",
			evidence: append(relationEvidence(thread), obligationEvidence(thread)...),
		}
	case previous.Goal != current.Goal || previous.Rationale != current.Rationale ||
		previous.Implications != current.Implications:
		return &candidate{
			kind: model.AttentionKnow, summary: "The goal's direction or implications changed",
			why:      "Durable intent or material consequences changed.",
			evidence: evidenceIDs(thread.Evidence),
		}
	case previous.Phase != current.Phase && (current.Phase == model.ThreadOperationalizing ||
		current.Phase == model.ThreadReflecting || current.Phase == model.ThreadComplete):
		return &candidate{
			kind: model.AttentionKnow, summary: "The goal advanced to " + string(current.Phase),
			why:      "The coordination lifecycle crossed a material boundary.",
			evidence: evidenceIDs(thread.Evidence),
		}
	default:
		return nil
	}
}

func moment(thread model.Thread, revision string, value candidate, now time.Time) model.AttentionMoment {
	return model.AttentionMoment{
		ID: thread.ID + "@" + revision, Kind: value.kind, Summary: value.summary,
		Why: value.why, Revision: revision, EvidenceIDs: uniqueStrings(value.evidence),
		CreatedAt: now, Seen: false,
	}
}

func whyNow(thread model.Thread) string {
	for index := len(thread.Attention) - 1; index >= 0; index-- {
		if !thread.Attention[index].Seen {
			return thread.Attention[index].Summary
		}
	}
	return "In " + string(thread.Phase)
}

func hasMergedArtifact(thread model.Thread) bool {
	for _, artifact := range thread.Artifacts {
		if artifact.Kind == model.ArtifactPullRequest && strings.EqualFold(artifact.State, "merged") {
			return true
		}
	}
	return false
}

func hasOpenObligation(thread model.Thread) bool {
	for _, obligation := range thread.Obligations {
		if !obligation.Satisfied {
			return true
		}
	}
	return false
}

func hasBoundaryImplication(thread model.Thread) bool {
	for _, implication := range thread.Implications {
		switch implication.Category {
		case "production", "security", "migration", "infrastructure", "operational":
			return true
		}
	}
	return false
}

func hasStaleEvidence(thread model.Thread) bool {
	for _, evidence := range thread.Evidence {
		if evidence.Freshness == "stale" {
			return true
		}
	}
	return false
}

func obligationEvidence(thread model.Thread) []string {
	var result []string
	for _, obligation := range thread.Obligations {
		if !obligation.Satisfied {
			result = append(result, obligation.EvidenceIDs...)
		}
	}
	return uniqueStrings(result)
}

func implicationEvidence(thread model.Thread) []string {
	var result []string
	for _, implication := range thread.Implications {
		result = append(result, implication.EvidenceIDs...)
	}
	return uniqueStrings(result)
}

func relationEvidence(thread model.Thread) []string {
	var result []string
	for _, relation := range thread.Dependencies {
		result = append(result, relation.EvidenceIDs...)
	}
	return uniqueStrings(result)
}

func evidenceIDs(values []model.EvidenceRef) []string {
	result := make([]string, 0, len(values))
	for _, evidence := range values {
		result = append(result, evidence.ID)
	}
	return result
}

func mergeStrings(groups ...[]string) []string {
	var result []string
	for _, group := range groups {
		result = append(result, group...)
	}
	return uniqueStrings(result)
}

func uniqueStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		if strings.TrimSpace(value) == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}

func digest(value any) string {
	contents, _ := json.Marshal(value)
	sum := sha256.Sum256(contents)
	return hex.EncodeToString(sum[:12])
}
