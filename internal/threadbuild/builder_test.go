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

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
