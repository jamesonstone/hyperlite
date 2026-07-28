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
	thread.Implications[0].Summary = "Audit history preserves how state changed."
	if value := currentCandidate(thread); value != nil {
		t.Fatalf("historical change language created attention: %#v", value)
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

func TestNonActionableDependencyChangeDoesNotMaskGoalChange(t *testing.T) {
	thread := model.Thread{
		Phase:    model.ThreadImplementing,
		Evidence: []model.EvidenceRef{{ID: "spec:1"}},
	}
	value := changedCandidate(
		MaterialSignature{Goal: "before", Dependencies: "before"},
		MaterialSignature{Goal: "after", Dependencies: "after"},
		thread,
	)
	if value == nil || value.kind != model.AttentionKnow ||
		value.summary != "The goal's direction or implications changed" {
		t.Fatalf("goal change was masked: %#v", value)
	}
}

func TestBoundaryEvidenceExcludesUnrelatedImplicationCategories(t *testing.T) {
	thread := model.Thread{
		Implications: []model.ThreadImplication{
			{
				Summary: "Deploy the production worker.", Category: "production",
				EvidenceIDs: []string{"production"},
			},
			{
				Summary: "Change the documentation.", Category: "documentation",
				EvidenceIDs: []string{"documentation"},
			},
		},
	}
	values := boundaryEvidence(thread)
	if len(values) != 1 || values[0] != "production" {
		t.Fatalf("boundary evidence = %#v", values)
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
