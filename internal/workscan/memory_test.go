package workscan

import (
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/memoryscan"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestScanRepositoryMemoryKeepsOnlyCurrentDurableLanes(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	repository := config.Repository{
		Name: "labcore", Path: "/repo/labcore", GitHub: "owner/labcore", Base: "main",
	}
	gh101 := "/worktrees/labcore/GH-101"
	gh102 := "/worktrees/labcore/GH-102"
	temporary := "/private/tmp/weekly/owner--labcore"
	stale := "/worktrees/labcore/GH-80"
	memory := fakeMemory{results: map[string]memoryscan.Result{
		gh101: {Documents: []memoryscan.Document{{
			FeatureID: "0018", Slug: "accessioning", Path: "docs/specs/0018-accessioning/SPEC.md",
			RepositoryRoot: gh101, IssueNumbers: []int{101}, UpdatedAt: now,
		}}},
		gh102: {Documents: []memoryscan.Document{
			{
				FeatureID: "0018", Slug: "coverage", Path: "docs/specs/0018-coverage/SPEC.md",
				RepositoryRoot: gh102, IssueNumbers: []int{102}, UpdatedAt: now,
			},
			{
				FeatureID: "0001", Slug: "historical", Path: "docs/specs/0001-historical/SPEC.md",
				RepositoryRoot: gh102, IssueNumbers: []int{16}, UpdatedAt: now,
			},
			{
				FeatureID: "0007", Slug: "unrelated", Path: "docs/specs/0007-unrelated/SPEC.md",
				RepositoryRoot: gh102, UpdatedAt: now,
			},
		}},
		temporary: {Documents: []memoryscan.Document{{
			FeatureID: "0089", Slug: "maintenance", Path: "docs/specs/0089-maintenance/SPEC.md",
			RepositoryRoot: temporary, UpdatedAt: now,
		}}},
		stale: {Documents: []memoryscan.Document{{
			FeatureID: "0080", Slug: "old", Path: "docs/specs/0080-old/SPEC.md",
			RepositoryRoot: stale, UpdatedAt: now.Add(-48 * time.Hour),
		}}},
	}}
	scanner := Scanner{Memory: memory}
	locals := []gitscan.LocalLane{
		laneForMemory("GH-101", gh101, now),
		laneForMemory("GH-102", gh102, now),
		laneForMemory("GH-89", temporary, now),
		laneForMemory("GH-80", stale, now.Add(-48*time.Hour)),
	}
	result := scanner.scanRepositoryMemory(repository, locals, 24*time.Hour, now)
	if len(result.Documents) != 2 ||
		result.Documents[0].Slug != "accessioning" ||
		result.Documents[1].Slug != "coverage" {
		t.Fatalf("documents = %#v", result.Documents)
	}
}

func laneForMemory(branch, path string, updatedAt time.Time) gitscan.LocalLane {
	return gitscan.LocalLane{
		Branch: branch, Publication: model.PublicationUnpushed,
		Worktree: model.Worktree{Path: path, Unstaged: 1, UpdatedAt: updatedAt},
	}
}

func TestDocumentIdentityIncludesExactIssueAnchor(t *testing.T) {
	document := memoryscan.Document{
		FeatureID: "0018", Slug: "feature", Path: "docs/specs/0018-feature/SPEC.md",
		IssueNumbers: []int{101},
	}
	other := document
	other.IssueNumbers = []int{102}
	if documentIdentity(document) == documentIdentity(other) {
		t.Fatal("different exact issue anchors shared one document identity")
	}
}
