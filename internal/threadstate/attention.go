package threadstate

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

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
	if thread.Phase == model.ThreadComplete {
		return nil
	}
	switch {
	case previous.Dependencies != current.Dependencies || previous.Obligations != current.Obligations:
		return &candidate{
			kind: model.AttentionReconcile, summary: "Dependencies or remaining obligations changed",
			why:      "The coordination path for this goal is materially different.",
			evidence: append(relationEvidence(thread), obligationEvidence(thread)...),
		}
	case previous.Review != current.Review:
		return &candidate{
			kind: model.AttentionKnow, summary: "Material review conclusions changed",
			why:      "Prior review decisions no longer reflect the latest evidence.",
			evidence: evidenceIDs(thread.Evidence),
		}
	case previous.Goal != current.Goal || previous.Rationale != current.Rationale ||
		previous.Implications != current.Implications:
		return &candidate{
			kind: model.AttentionKnow, summary: "The goal's direction or implications changed",
			why:      "Durable intent or material consequences changed.",
			evidence: evidenceIDs(thread.Evidence),
		}
	case previous.Phase != current.Phase && (current.Phase == model.ThreadOperationalizing ||
		current.Phase == model.ThreadReflecting):
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
	if thread.Phase == model.ThreadComplete {
		return "Complete"
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
