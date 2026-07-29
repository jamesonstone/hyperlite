package threadstate

import (
	"sort"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func retireUnsupportedMoments(
	moments []model.AttentionMoment,
	thread model.Thread,
	revision string,
) {
	for index := range moments {
		if !moments[index].Seen &&
			!momentSupported(moments[index], thread, revision) {
			moments[index].Seen = true
		}
	}
}

func momentSupported(
	moment model.AttentionMoment,
	thread model.Thread,
	revision string,
) bool {
	if !thread.Active {
		return false
	}
	switch moment.Summary {
	case mergedObligationSummary:
		return hasOperationalObligation(thread)
	case boundarySummary:
		return (thread.Phase == model.ThreadReviewing ||
			thread.Phase == model.ThreadOperationalizing) &&
			hasActionableBoundary(thread)
	case dependencyChangeSummary:
		return moment.Revision == revision &&
			(hasOperationalObligation(thread) || hasActionableCoordination(thread))
	case coordinationSummary:
		return hasActionableCoordination(thread)
	case staleSummary:
		return highConsequenceUncertainty(thread)
	}
	if moment.Kind == model.AttentionDecide {
		for _, implication := range thread.Implications {
			if implication.Category == "review_decision" &&
				implication.Summary == moment.Summary {
				return true
			}
		}
		return false
	}
	return false
}

func sameAttentionSituation(previous, current *candidate) bool {
	if previous == nil || current == nil || previous.kind != current.kind {
		return false
	}
	return previous.fingerprint != "" &&
		previous.fingerprint == current.fingerprint
}

func staleEvidenceRefs(thread model.Thread) []model.EvidenceRef {
	var values []model.EvidenceRef
	for _, evidence := range thread.Evidence {
		if evidence.Freshness == "stale" {
			values = append(values, evidence)
		}
	}
	sort.Slice(values, func(i, j int) bool { return values[i].ID < values[j].ID })
	return values
}

func appendAttentionMoment(
	moments []model.AttentionMoment,
	thread model.Thread,
	revision string,
	value candidate,
	now time.Time,
) []model.AttentionMoment {
	for index := range moments {
		if !moments[index].Seen &&
			moments[index].Kind == value.kind &&
			moments[index].Summary == value.summary {
			moments[index].Seen = true
		}
	}
	return append(moments, moment(thread, revision, value, now))
}

func openObligationFingerprint(thread model.Thread) string {
	var values []model.ThreadObligation
	for _, obligation := range thread.Obligations {
		if !obligation.Satisfied {
			values = append(values, obligation)
		}
	}
	return digest(values)
}

func boundaryFingerprint(thread model.Thread) string {
	var values []string
	for _, implication := range thread.Implications {
		if boundaryCategory(implication.Category) &&
			actionableBoundaryStatement(implication.Summary) {
			values = append(values, implication.Summary)
		}
	}
	for _, obligation := range thread.Obligations {
		if !obligation.Satisfied &&
			actionableBoundaryStatement(obligation.Summary) {
			values = append(values, obligation.Summary)
		}
	}
	return digest(values)
}

func coordinationFingerprint(thread model.Thread) string {
	var values []model.ThreadRelation
	for _, relation := range thread.Dependencies {
		if relation.Basis != model.BasisHypothesis &&
			(relation.Kind == model.RelationDependsOn ||
				relation.Kind == model.RelationMustPrecede) {
			values = append(values, relation)
		}
	}
	return digest(values)
}
