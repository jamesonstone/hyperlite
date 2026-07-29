package gitscan

import (
	"testing"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestIssueIdentityRequiresExactIssueBranch(t *testing.T) {
	for value, expected := range map[string]int{
		"GH-7":         7,
		"gh-8":         8,
		"GH-7-extra":   0,
		"feature/GH-7": 0,
		"":             0,
	} {
		if actual := IssueNumber(value); actual != expected {
			t.Fatalf("IssueNumber(%q) = %d, want %d", value, actual, expected)
		}
	}

	detached := LocalLane{
		Branch: "HEAD",
		Worktree: model.Worktree{
			Path: "/repo/worktrees/GH-9", Detached: true,
		},
	}
	if actual := IdentityBranch(detached); actual != "GH-9" {
		t.Fatalf("detached identity = %q", actual)
	}
	detached.Worktree.Path = "/repo/worktrees/experiment"
	if actual := IdentityBranch(detached); actual != "HEAD" {
		t.Fatalf("experimental identity = %q", actual)
	}
}
