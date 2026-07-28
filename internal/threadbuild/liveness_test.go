package threadbuild

import (
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/memoryscan"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestTerminalOnlyPullRequestIsDormantWithoutClaimingCompletion(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	threads := Build(Input{
		Repository: config.Repository{Name: "repo", GitHub: "owner/repo"},
		Remote: model.RemoteEvidence{PullRequests: []model.PullRequest{{
			Number: 2, Title: "Delivered", State: "MERGED", MergedAt: now,
			HeadRefName: "GH-1", HeadRefOID: "head", UpdatedAt: now,
		}}},
		StaleAfter: 24 * time.Hour,
		Now:        now,
	})
	if len(threads) != 1 ||
		threads[0].Phase != model.ThreadReflecting ||
		threads[0].Active {
		t.Fatalf("threads = %#v", threads)
	}
}

func TestOldMergedPullRequestCorrelatesWithCleanWorktree(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	old := now.Add(-60 * 24 * time.Hour)
	threads := Build(Input{
		Repository: config.Repository{Name: "repo", GitHub: "owner/repo", Base: "main"},
		Locals: []gitscan.LocalLane{{
			Branch: "GH-3", Publication: model.PublicationPublished,
			Worktree: model.Worktree{
				Path: "/repo/GH-3", HeadOID: "later-clean-head",
				AheadBase: 1, UpdatedAt: old,
			},
		}},
		Remote: model.RemoteEvidence{PullRequests: []model.PullRequest{{
			Number: 4, Title: "Delivered", State: "MERGED", MergedAt: old,
			HeadRefName: "GH-3", HeadRefOID: "merged-head", UpdatedAt: old,
		}}},
		StaleAfter: 24 * time.Hour,
		Now:        now,
	})
	if len(threads) != 1 ||
		len(threads[0].Artifacts) != 2 ||
		threads[0].Title != "Delivered" ||
		threads[0].Phase != model.ThreadReflecting ||
		threads[0].Active {
		t.Fatalf("threads = %#v", threads)
	}
}

func TestCleanPublishedWorktreeAheadOfBaseIsDormant(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	threads := Build(Input{
		Repository: config.Repository{Name: "repo", GitHub: "owner/repo", Base: "main"},
		Locals: []gitscan.LocalLane{{
			Branch: "GH-3", Publication: model.PublicationPublished,
			Worktree: model.Worktree{
				Path: "/repo/GH-3", HeadOID: "published-head",
				AheadBase: 1, UpdatedAt: now,
			},
		}},
		StaleAfter: 24 * time.Hour,
		Now:        now,
	})
	if len(threads) != 1 ||
		threads[0].Phase != model.ThreadImplementing ||
		threads[0].Active {
		t.Fatalf("threads = %#v", threads)
	}
}

func TestIsolatedSpecLivenessUsesConfiguredStaleness(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	threads := Build(Input{
		Repository: config.Repository{Name: "repo", GitHub: "owner/repo"},
		Documents: []memoryscan.Document{
			{
				ID: "spec:0001", FeatureID: "0001", Title: "Dormant",
				Phase: "clarify", WorkflowVersion: 2,
				Path:      "docs/specs/0001-dormant/SPEC.md",
				UpdatedAt: now.Add(-25 * time.Hour),
			},
			{
				ID: "spec:0002", FeatureID: "0002", Title: "Current",
				Phase: "clarify", WorkflowVersion: 2,
				Path:      "docs/specs/0002-current/SPEC.md",
				UpdatedAt: now.Add(-time.Hour),
			},
		},
		StaleAfter: 24 * time.Hour,
		Now:        now,
	})
	active := map[string]bool{}
	for _, thread := range threads {
		active[thread.Title] = thread.Active
	}
	if active["Dormant"] || !active["Current"] {
		t.Fatalf("active = %#v", active)
	}
}
