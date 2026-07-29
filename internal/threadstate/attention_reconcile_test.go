package threadstate

import (
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestReconcileRetiresUnsupportedActiveMoment(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := Empty()
	thread := model.Thread{
		ID: "issue:owner/repo#1", Aliases: []string{"issue:owner/repo#1"},
		Title: "Feature", Goal: "Deliver feature", Rationale: "Needed",
		Phase: model.ThreadReviewing, Active: true,
		Repositories: []string{"owner/repo"},
		Implications: []model.ThreadImplication{{
			Summary: "Deploy the production worker.", Category: "production",
			Basis: model.BasisExtracted, EvidenceIDs: []string{"spec:1"},
		}},
		Evidence: []model.EvidenceRef{{ID: "spec:1", Freshness: "current"}},
	}
	values := ReconcileSelected(
		&state, []model.Thread{thread}, []string{"owner/repo"}, now,
	)
	if len(values) != 1 || len(values[0].Attention) != 1 ||
		values[0].Attention[0].Seen {
		t.Fatalf("initial attention = %#v", values)
	}
	moment := values[0].Attention[0]
	if moment.Action == "" || moment.Consequence == "" || moment.ValidWhile == "" {
		t.Fatalf("attention contract is incomplete: %#v", moment)
	}

	thread.Implications[0].Summary = "Never deploy this check to production."
	values = ReconcileSelected(
		&state, []model.Thread{thread}, []string{"owner/repo"}, now.Add(time.Minute),
	)
	if len(values) != 1 || len(values[0].Attention) != 1 ||
		!values[0].Attention[0].Seen || values[0].WhyNow != "In reviewing" {
		t.Fatalf("unsupported attention remained unread: %#v", values)
	}
}

func TestReconcileIgnoresGoalMetadataEnrichment(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := Empty()
	thread := model.Thread{
		ID: "issue:owner/repo#2", Aliases: []string{"issue:owner/repo#2"},
		Title: "Feature", Goal: "Initial goal", Rationale: "Needed",
		Phase: model.ThreadImplementing, Active: true,
		Repositories: []string{"owner/repo"},
		Evidence:     []model.EvidenceRef{{ID: "spec:1", Freshness: "current"}},
	}
	ReconcileSelected(&state, []model.Thread{thread}, []string{"owner/repo"}, now)

	thread.Goal = "Changed goal"
	values := ReconcileSelected(
		&state, []model.Thread{thread}, []string{"owner/repo"}, now.Add(time.Minute),
	)
	if len(values[0].Attention) != 0 {
		t.Fatalf("goal metadata enrichment created attention: %#v", values[0].Attention)
	}
}

func TestAcknowledgedSituationSurvivesUnrelatedEvidenceRevision(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := Empty()
	thread := model.Thread{
		ID: "issue:owner/repo#3", Aliases: []string{"issue:owner/repo#3"},
		Title: "Feature", Goal: "Deliver feature", Rationale: "Needed",
		Phase: model.ThreadOperationalizing, Active: true,
		Repositories: []string{"owner/repo"},
		Artifacts: []model.ThreadArtifact{{
			Kind: model.ArtifactPullRequest, State: "merged",
		}},
		Obligations: []model.ThreadObligation{{
			Summary: "Deploy the service.", EvidenceIDs: []string{"spec:1"},
		}},
		Evidence: []model.EvidenceRef{{ID: "spec:1", Freshness: "current"}},
	}
	values := ReconcileSelected(
		&state, []model.Thread{thread}, []string{"owner/repo"}, now,
	)
	if len(values[0].Attention) != 1 {
		t.Fatalf("initial attention = %#v", values[0].Attention)
	}
	if err := MarkSeen(&state, thread.ID, values[0].LatestMaterialRevision); err != nil {
		t.Fatal(err)
	}

	thread.Rationale = "Needed with more hydrated context"
	values = ReconcileSelected(
		&state, []model.Thread{thread}, []string{"owner/repo"}, now.Add(time.Minute),
	)
	if len(values[0].Attention) != 1 || !values[0].Attention[0].Seen {
		t.Fatalf("unchanged situation demanded attention again: %#v", values[0].Attention)
	}

	thread.Obligations = []model.ThreadObligation{{
		Summary:     "Deploy the service and migrate traffic.",
		EvidenceIDs: []string{"spec:1"},
	}}
	values = ReconcileSelected(
		&state, []model.Thread{thread}, []string{"owner/repo"}, now.Add(2*time.Minute),
	)
	if len(values[0].Attention) != 2 || !values[0].Attention[0].Seen ||
		values[0].Attention[1].Seen {
		t.Fatalf("changed obligation did not create new attention: %#v", values[0].Attention)
	}
}
