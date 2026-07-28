package threadstate

import (
	"testing"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestChangedCandidateDetectsRemovedReviewConclusion(t *testing.T) {
	thread := model.Thread{
		Evidence: []model.EvidenceRef{{ID: "review:1"}},
	}
	value := changedCandidate(
		MaterialSignature{Review: "Architecture ownership must be decided"},
		MaterialSignature{},
		thread,
	)
	if value == nil ||
		value.kind != model.AttentionKnow ||
		value.summary != "Material review conclusions changed" {
		t.Fatalf("candidate = %#v", value)
	}
}

func TestWhyNowDescribesCompletedProjectionWithoutAmbiguity(t *testing.T) {
	thread := model.Thread{Phase: model.ThreadComplete}

	if got := whyNow(thread); got != "Complete" {
		t.Fatalf("whyNow() = %q, want Complete", got)
	}
}
