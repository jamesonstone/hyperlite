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

func TestBoundaryAttentionRequiresActionableProspectiveChange(t *testing.T) {
	thread := model.Thread{
		Phase: model.ThreadReviewing,
		Implications: []model.ThreadImplication{{
			Summary:  "Never point the fail-closed check at production.",
			Category: "production",
		}},
	}
	if value := currentCandidate(thread); value != nil {
		t.Fatalf("negative safety statement created attention: %#v", value)
	}
	thread.Implications[0].Summary = "Production object storage ownership changes."
	value := currentCandidate(thread)
	if value == nil || value.kind != model.AttentionGuard ||
		value.summary != boundarySummary {
		t.Fatalf("actionable boundary candidate = %#v", value)
	}
	thread.Implications[0].Summary = "Deploy production with no downtime."
	if value := currentCandidate(thread); value == nil {
		t.Fatal("non-disruptive delivery language hid an actionable boundary")
	}
}

func TestSatisfiedObligationChangeDoesNotCreateAttention(t *testing.T) {
	thread := model.Thread{
		Phase: model.ThreadImplementing,
		Obligations: []model.ThreadObligation{{
			Summary: "Deploy production.", Satisfied: true,
		}},
	}
	value := changedCandidate(
		MaterialSignature{Obligations: "before"},
		MaterialSignature{Obligations: "after"},
		thread,
	)
	if value != nil {
		t.Fatalf("satisfied obligation created attention: %#v", value)
	}
}

func TestOnlyAuthoritativeCoordinationRelationsCreateAttention(t *testing.T) {
	thread := model.Thread{
		Phase: model.ThreadImplementing,
		Dependencies: []model.ThreadRelation{{
			Kind: model.RelationDependsOn, Basis: model.BasisHypothesis,
		}},
	}
	if value := currentCandidate(thread); value != nil {
		t.Fatalf("hypothesis created attention: %#v", value)
	}
	thread.Dependencies[0].Basis = model.BasisExplicit
	value := currentCandidate(thread)
	if value == nil || value.kind != model.AttentionReconcile ||
		value.summary != coordinationSummary {
		t.Fatalf("authoritative dependency candidate = %#v", value)
	}
}
