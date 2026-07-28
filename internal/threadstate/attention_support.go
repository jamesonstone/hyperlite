package threadstate

import "github.com/jamesonstone/hyperlite/internal/model"

func retireUnsupportedMoments(moments []model.AttentionMoment, thread model.Thread) {
	for index := range moments {
		if !moments[index].Seen && !momentSupported(moments[index], thread) {
			moments[index].Seen = true
		}
	}
}

func momentSupported(moment model.AttentionMoment, thread model.Thread) bool {
	switch moment.Summary {
	case mergedObligationSummary:
		return hasMergedArtifact(thread) && hasOpenObligation(thread)
	case boundarySummary:
		return (thread.Phase == model.ThreadReviewing ||
			thread.Phase == model.ThreadOperationalizing) &&
			hasActionableBoundary(thread)
	case "Dependencies or remaining obligations changed", coordinationSummary:
		return hasOpenObligation(thread) || hasCoordinationRelation(thread)
	case staleSummary:
		return hasStaleEvidence(thread)
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
	return true
}
