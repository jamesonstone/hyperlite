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

const (
	mergedObligationSummary = "Implementation advanced, but operational obligations remain"
	boundarySummary         = "A consequential change is approaching a delivery boundary"
	coordinationSummary     = "Execution order or dependency requires coordination"
	dependencyChangeSummary = "Dependencies or remaining obligations changed"
	staleSummary            = "Thread conclusions rely on incomplete or stale evidence"
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
	kind        model.AttentionKind
	fingerprint string
	summary     string
	action      string
	why         string
	consequence string
	validWhile  string
	evidence    []string
}

func currentCandidate(thread model.Thread) *candidate {
	if !thread.Active {
		return nil
	}
	if highConsequenceUncertainty(thread) {
		return &candidate{
			kind: model.AttentionUncertain, summary: staleSummary,
			fingerprint: staleSummary,
			action:      "Verify the stale evidence before authorizing the consequential boundary.",
			why:         "Hyperlite cannot safely infer the current coordination state.",
			consequence: "A consequential action may rely on an unsupported coordination conclusion.",
			validWhile:  "The thread remains current and consequential while authoritative evidence is stale.",
			evidence:    evidenceIDs(thread.Evidence),
		}
	}
	for _, implication := range thread.Implications {
		if implication.Category == "review_decision" {
			return &candidate{
				kind: model.AttentionDecide, summary: implication.Summary,
				fingerprint: digest(implication),
				action:      "Decide whether to accept or redirect the challenged direction.",
				why:         "Review evidence challenges a material direction or boundary.",
				consequence: "Implementation may continue against an unsettled project boundary.",
				validWhile:  "The cited review decision remains unresolved and the thread remains current.",
				evidence:    implication.EvidenceIDs,
			}
		}
	}
	if hasOperationalObligation(thread) {
		return &candidate{
			kind: model.AttentionReconcile, summary: mergedObligationSummary,
			fingerprint: openObligationFingerprint(thread),
			action:      "Confirm ownership and completion order for the remaining operational obligation.",
			why:         "Artifact completion does not complete the larger goal.",
			consequence: "The implementation may be treated as delivered before the larger outcome is operational.",
			validWhile:  "A merged implementation artifact and an unsatisfied operational obligation remain current.",
			evidence:    obligationEvidence(thread),
		}
	}
	if (thread.Phase == model.ThreadReviewing ||
		thread.Phase == model.ThreadOperationalizing) &&
		hasActionableBoundary(thread) {
		return &candidate{
			kind: model.AttentionGuard, summary: boundarySummary,
			fingerprint: boundaryFingerprint(thread),
			action:      "Review and authorize the consequential boundary before merge or activation.",
			why:         "Production, security, migration, or infrastructure implications should be understood before merge.",
			consequence: "A consequential change may proceed without informed coordination.",
			validWhile:  "The thread remains current, near delivery, and the cited boundary action is still prospective.",
			evidence:    boundaryEvidence(thread),
		}
	}
	if hasActionableCoordination(thread) {
		return &candidate{
			kind: model.AttentionReconcile, summary: coordinationSummary,
			fingerprint: coordinationFingerprint(thread),
			action:      "Reconcile execution order with the authoritative dependency.",
			why:         "An authoritative dependency or execution order affects how this goal can proceed.",
			consequence: "Parallel work may proceed in an invalid or unsafe order.",
			validWhile:  "The thread remains current and the authoritative dependency still affects execution.",
			evidence:    relationEvidence(thread),
		}
	}
	return nil
}

func changedCandidate(previous, current MaterialSignature, thread model.Thread) *candidate {
	if !thread.Active {
		return nil
	}
	if candidate := currentCandidate(thread); candidate != nil {
		return candidate
	}
	if thread.Phase == model.ThreadComplete {
		return nil
	}
	if (previous.Dependencies != current.Dependencies ||
		previous.Obligations != current.Obligations) &&
		(hasOperationalObligation(thread) || hasActionableCoordination(thread)) {
		return &candidate{
			kind: model.AttentionReconcile, summary: dependencyChangeSummary,
			fingerprint: current.Dependencies + "\x1f" + current.Obligations,
			action:      "Reconcile the changed execution path before work proceeds.",
			why:         "The coordination path for this goal is materially different.",
			consequence: "Parallel work may continue with obsolete dependencies or ordering.",
			validWhile:  "This is the latest material revision and its coordination requirement remains current.",
			evidence:    append(relationEvidence(thread), obligationEvidence(thread)...),
		}
	}
	return nil
}

func moment(thread model.Thread, revision string, value candidate, now time.Time) model.AttentionMoment {
	return model.AttentionMoment{
		ID: thread.ID + "@" + revision, Kind: value.kind, Summary: value.summary,
		Action: value.action, Why: value.why, Consequence: value.consequence,
		ValidWhile: value.validWhile, Revision: revision,
		EvidenceIDs: uniqueStrings(value.evidence),
		CreatedAt:   now, Seen: false,
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

func hasCoordinationRelation(thread model.Thread) bool {
	for _, relation := range thread.Dependencies {
		if relation.Basis != model.BasisHypothesis &&
			(relation.Kind == model.RelationDependsOn ||
				relation.Kind == model.RelationMustPrecede) {
			return true
		}
	}
	return false
}

func hasActionableCoordination(thread model.Thread) bool {
	if !hasCoordinationRelation(thread) {
		return false
	}
	switch thread.Phase {
	case model.ThreadPlanned, model.ThreadImplementing,
		model.ThreadReviewing, model.ThreadOperationalizing:
		return true
	default:
		return false
	}
}

func hasOperationalObligation(thread model.Thread) bool {
	return hasMergedArtifact(thread) && hasOpenObligation(thread)
}

func highConsequenceUncertainty(thread model.Thread) bool {
	if !hasStaleEvidence(thread) {
		return false
	}
	return hasOperationalObligation(thread) ||
		reviewSignature(thread) != "" ||
		((thread.Phase == model.ThreadReviewing ||
			thread.Phase == model.ThreadOperationalizing) &&
			(hasActionableBoundary(thread) || hasActionableCoordination(thread)))
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
