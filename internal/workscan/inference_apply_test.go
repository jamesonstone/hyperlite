package workscan

import (
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/threadstate"
)

func TestSemanticHypothesisCannotMergeOrCompleteThreads(t *testing.T) {
	thread := model.Thread{
		ID: "issue:owner/event-sink#20", Aliases: []string{"issue:owner/event-sink#20"},
		Phase: model.ThreadOperationalizing, Active: true,
		Obligations: []model.ThreadObligation{{
			ID: "deploy", Summary: "Deploy infrastructure", Basis: model.BasisExtracted,
		}},
	}
	applyInference(&thread, model.InferenceThread{
		ThreadID: thread.ID,
		Relations: []model.InferenceRelation{{
			Kind: model.RelationDependsOn, TargetThreadID: "issue:owner/r2#10",
			Target: "R2 storage", Basis: model.BasisHypothesis, Confidence: 0.5,
			EvidenceIDs: []string{"spec:event-sink"},
		}},
	})
	if thread.ID != "issue:owner/event-sink#20" || thread.Phase != model.ThreadOperationalizing ||
		!thread.Active || len(thread.Obligations) != 1 {
		t.Fatalf("hypothesis changed authoritative state: %#v", thread)
	}
	if len(thread.Dependencies) != 1 || thread.Dependencies[0].Basis != model.BasisHypothesis {
		t.Fatalf("hypothesis was not retained as a qualified relation: %#v", thread.Dependencies)
	}
}

func TestReviewSignificanceControlsAttention(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	base := model.Thread{
		ID: "issue:owner/repo#1", Aliases: []string{"issue:owner/repo#1"},
		Title: "Feature", Goal: "Deliver feature", Rationale: "Needed",
		Phase: model.ThreadReviewing, Active: true,
		Evidence: []model.EvidenceRef{{ID: "review:1", Freshness: "current"}},
	}
	routine := base
	applyInference(&routine, model.InferenceThread{
		ThreadID: routine.ID, ReviewSignificant: false,
		ReviewSummary: model.InferenceClaim{Text: "Rename the local variable", EvidenceIDs: []string{"review:1"}},
	})
	state := threadstate.Empty()
	values := threadstate.Reconcile(&state, []model.Thread{routine}, now)
	if len(values[0].Attention) != 0 {
		t.Fatalf("routine repair created attention: %#v", values[0].Attention)
	}

	architectural := base
	applyInference(&architectural, model.InferenceThread{
		ThreadID: architectural.ID, ReviewSignificant: true, Confidence: 0.9,
		ReviewSummary: model.InferenceClaim{
			Text:        "Ownership must move before the public contract changes",
			EvidenceIDs: []string{"review:1"},
		},
	})
	state = threadstate.Empty()
	values = threadstate.Reconcile(&state, []model.Thread{architectural}, now)
	if len(values[0].Attention) != 1 || values[0].Attention[0].Kind != model.AttentionDecide {
		t.Fatalf("architectural review attention = %#v", values[0].Attention)
	}
}

func TestMaterialReviewRevivesDormantOpenPullRequest(t *testing.T) {
	thread := model.Thread{
		ID: "issue:owner/repo#2", Phase: model.ThreadReviewing,
		Artifacts: []model.ThreadArtifact{{
			Kind: model.ArtifactPullRequest, State: "open",
		}},
	}
	applyInference(&thread, model.InferenceThread{
		ThreadID: thread.ID, ReviewSignificant: true,
		ReviewSummary: model.InferenceClaim{
			Text: "Ownership must be decided before the contract changes.",
		},
	})
	if !thread.Active {
		t.Fatal("material review decision did not revive the current working set")
	}
}

func TestEvidenceMentionsCreateCitedCrossThreadHypothesisOnly(t *testing.T) {
	threads := []model.Thread{
		{
			ID: "issue:owner/event-sink#26", Active: true, Repositories: []string{"owner/event-sink"},
			Evidence: []model.EvidenceRef{{
				ID: "spec:event", Kind: "spec",
				Excerpt: "R2 retains policy authority while Event Sink owns immutable history.",
			}},
		},
		{
			ID: "issue:owner/r2#21", Active: true, Repositories: []string{"owner/r2"},
		},
		{
			ID: "branch:owner/r2@main", Active: true, Repositories: []string{"owner/r2"},
		},
	}
	resolveRelations(threads)
	relations := threads[0].Dependencies
	if len(relations) != 1 || relations[0].TargetThreadID != "issue:owner/r2#21" ||
		relations[0].Basis != model.BasisHypothesis ||
		len(relations[0].EvidenceIDs) != 1 || relations[0].EvidenceIDs[0] != "spec:event" {
		t.Fatalf("relations = %#v", relations)
	}
}

func TestSortRelationsUsesCompleteDeterministicOrder(t *testing.T) {
	relations := []model.ThreadRelation{
		{
			Kind: model.RelationAffects, Target: "r2", TargetThreadID: "thread:b",
			Basis: model.BasisHypothesis, EvidenceIDs: []string{"evidence:b"},
		},
		{
			Kind: model.RelationAffects, Target: "r2", TargetThreadID: "thread:a",
			Basis: model.BasisHypothesis, EvidenceIDs: []string{"evidence:a"},
		},
	}
	sortRelations(relations)
	if relations[0].TargetThreadID != "thread:a" || relations[1].TargetThreadID != "thread:b" {
		t.Fatalf("relations = %#v", relations)
	}
}
