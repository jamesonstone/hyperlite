package threadbuild

import (
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/memoryscan"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestExactCorrelationAndMergedOperationalClosure(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	repository := config.Repository{Name: "r2", Path: "/repo/r2", GitHub: "owner/r2", Base: "main"}
	issue := model.Issue{
		Number: 10, Title: "R2 storage", State: "OPEN",
		URL: "https://github.com/owner/r2/issues/10", UpdatedAt: now,
	}
	merged := model.PullRequest{
		Number: 11, Title: "Implement R2", State: "MERGED", MergedAt: now,
		URL: "https://github.com/owner/r2/pull/11", HeadRefName: "GH-10",
		ClosingIssues: []model.Issue{issue}, UpdatedAt: now,
	}
	document := memoryscan.Document{
		ID: "spec:0001", FeatureID: "0001", Title: "R2 storage", Phase: "implement",
		Selected: true, Path: "docs/specs/0001-r2/SPEC.md",
		Purpose: "Store durable payloads.", Context: "Production infrastructure must be deployed.",
		IssueURLs: []string{issue.URL}, UpdatedAt: now,
		Obligations: []memoryscan.Candidate{{Summary: "Deploy the production R2 bucket."}},
	}
	threads := Build(Input{
		Repository: repository, Remote: model.RemoteEvidence{
			PullRequests: []model.PullRequest{merged}, Issues: []model.Issue{issue},
		},
		Documents: []memoryscan.Document{document}, Now: now,
	})
	if len(threads) != 1 {
		t.Fatalf("threads = %#v", threads)
	}
	thread := threads[0]
	if thread.ID != "issue:owner/r2#10" || thread.Phase != model.ThreadOperationalizing {
		t.Fatalf("thread = %#v", thread)
	}
	if len(thread.Obligations) != 1 || thread.Obligations[0].Satisfied {
		t.Fatalf("obligations = %#v", thread.Obligations)
	}
	for _, alias := range []string{
		"spec:owner/r2:0001", "branch:owner/r2@GH-10", "pr:owner/r2#11",
	} {
		if !contains(thread.Aliases, alias) {
			t.Fatalf("alias %q missing from %#v", alias, thread.Aliases)
		}
	}
}

func TestArtifactTransitionAloneDoesNotCloseGoal(t *testing.T) {
	now := time.Now().UTC()
	repository := config.Repository{Name: "r2", Path: "/repo/r2", GitHub: "owner/r2", Base: "main"}
	merged := model.PullRequest{
		Number: 11, Title: "Implement R2", State: "MERGED", MergedAt: now,
		URL: "https://github.com/owner/r2/pull/11", HeadRefName: "GH-10", UpdatedAt: now,
	}
	document := memoryscan.Document{
		ID: "spec:0001", FeatureID: "0001", Title: "R2", Phase: "implement",
		Selected: true, Path: "docs/specs/0001-r2/SPEC.md", UpdatedAt: now,
		Obligations: []memoryscan.Candidate{{Summary: "Deploy infrastructure."}},
	}
	threads := Build(Input{Repository: repository, Remote: model.RemoteEvidence{
		PullRequests: []model.PullRequest{merged},
	}, Documents: []memoryscan.Document{document}, Now: now})
	if len(threads) != 2 {
		t.Fatalf("uncorrelated PR and spec should remain separate: %#v", threads)
	}
	for _, thread := range threads {
		if thread.Phase == model.ThreadComplete {
			t.Fatalf("artifact transition closed a goal without canonical closure: %#v", thread)
		}
	}
}

func TestCanonicalClosureRequiresResolvedAnchorsAndObligations(t *testing.T) {
	now := time.Now().UTC()
	repository := config.Repository{Name: "r2", Path: "/repo/r2", GitHub: "owner/r2", Base: "main"}
	document := memoryscan.Document{
		ID: "spec:0001", FeatureID: "0001", Title: "R2", Phase: "deliver",
		Path: "docs/specs/0001-r2/SPEC.md", UpdatedAt: now,
		IssueURLs:   []string{"https://github.com/owner/r2/issues/10"},
		Obligations: []memoryscan.Candidate{{Summary: "Deploy infrastructure."}},
	}
	openIssue := model.Issue{
		Number: 10, Title: "R2", State: "OPEN",
		URL: "https://github.com/owner/r2/issues/10", UpdatedAt: now,
	}
	threads := Build(Input{Repository: repository, Remote: model.RemoteEvidence{
		Issues: []model.Issue{openIssue},
	}, Documents: []memoryscan.Document{document}, Now: now})
	if len(threads) != 1 || threads[0].Phase != model.ThreadOperationalizing {
		t.Fatalf("unresolved canonical thread = %#v", threads)
	}

	document.Obligations[0].Satisfied = true
	closedIssue := openIssue
	closedIssue.State = "CLOSED"
	threads = Build(Input{Repository: repository, Remote: model.RemoteEvidence{
		Issues: []model.Issue{closedIssue},
	}, Documents: []memoryscan.Document{document}, Now: now})
	if len(threads) != 1 || threads[0].Phase != model.ThreadComplete {
		t.Fatalf("resolved canonical thread = %#v", threads)
	}
}

func TestCleanStaleWorktreeDoesNotCreateThread(t *testing.T) {
	now := time.Now().UTC()
	threads := Build(Input{
		Repository: config.Repository{Name: "repo", Path: "/repo", GitHub: "owner/repo", Base: "main"},
		Locals: []gitscan.LocalLane{{
			Branch: "GH-1", Publication: model.PublicationPublished,
			Worktree: model.Worktree{Path: "/repo/worktree", UpdatedAt: now.Add(-90 * 24 * time.Hour)},
		}},
		Now: now,
	})
	if len(threads) != 0 {
		t.Fatalf("clean stale worktree created threads: %#v", threads)
	}
}

func TestOldTerminalIssueBranchPullRequestDoesNotCreateThread(t *testing.T) {
	now := time.Now().UTC()
	threads := Build(Input{
		Repository: config.Repository{Name: "repo", GitHub: "owner/repo"},
		Remote: model.RemoteEvidence{PullRequests: []model.PullRequest{{
			Number: 4, Title: "Old experiment", State: "MERGED",
			HeadRefName: "GH-3", UpdatedAt: now.Add(-31 * 24 * time.Hour),
		}}},
		Now: now,
	})
	if len(threads) != 0 {
		t.Fatalf("old terminal pull request created a thread: %#v", threads)
	}
}

func TestDerivedPhasePreservesAnyOpenIssue(t *testing.T) {
	thread := model.Thread{
		Phase: model.ThreadComplete,
		Artifacts: []model.ThreadArtifact{
			{Kind: model.ArtifactPullRequest, State: "merged"},
			{Kind: model.ArtifactIssue, State: "open"},
			{Kind: model.ArtifactIssue, State: "closed"},
		},
	}
	if phase := derivedPhase(thread, true, 1); phase != model.ThreadOperationalizing {
		t.Fatalf("phase = %q, want operationalizing", phase)
	}
}

func TestMultipleDocumentsDoNotEraseCanonicalFields(t *testing.T) {
	now := time.Now().UTC()
	issueURL := "https://github.com/owner/repo/issues/7"
	documents := []memoryscan.Document{
		{
			ID: "spec:0001", FeatureID: "0001", Title: "Canonical",
			Purpose: "Canonical goal.", Context: "Canonical rationale.",
			Phase: "implement", IssueURLs: []string{issueURL}, UpdatedAt: now,
		},
		{
			ID: "spec:0002", FeatureID: "0002", Title: "Follow-up",
			Phase: "delivery", IssueURLs: []string{issueURL}, UpdatedAt: now,
		},
	}
	threads := Build(Input{
		Repository: config.Repository{Name: "repo", GitHub: "owner/repo"},
		Documents:  documents,
		Now:        now,
	})
	if len(threads) != 1 ||
		threads[0].Title != "Canonical" ||
		threads[0].Goal != "Canonical goal." ||
		threads[0].Rationale != "Canonical rationale." ||
		threads[0].Phase != model.ThreadImplementing {
		t.Fatalf("thread = %#v", threads)
	}
}

func TestReflectionPhaseFollowsWorkflowVersion(t *testing.T) {
	now := time.Now().UTC()
	threads := Build(Input{
		Repository: config.Repository{Name: "repo", GitHub: "owner/repo"},
		Documents: []memoryscan.Document{
			{
				ID: "spec:0001", FeatureID: "0001", Title: "Legacy",
				Phase: "reflect", Path: "docs/specs/0001-legacy/SPEC.md", UpdatedAt: now,
			},
			{
				ID: "spec:0002", FeatureID: "0002", Title: "Living",
				Phase: "reflect", WorkflowVersion: 2,
				Path: "docs/specs/0002-living/SPEC.md", UpdatedAt: now,
			},
		},
		Now: now,
	})
	if len(threads) != 2 {
		t.Fatalf("threads = %#v", threads)
	}
	phases := map[string]model.ThreadPhase{}
	for _, thread := range threads {
		phases[thread.Title] = thread.Phase
	}
	if phases["Legacy"] != model.ThreadComplete || phases["Living"] != model.ThreadReflecting {
		t.Fatalf("phases = %#v", phases)
	}
}

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
