package prindex

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestProjectionStampsIssueLinksFromKitConfig(t *testing.T) {
	now := time.Date(2026, 11, 4, 18, 0, 0, 0, time.UTC)
	linearRoot := t.TempDir()
	githubRoot := t.TempDir()
	brokenRoot := t.TempDir()
	if err := os.WriteFile(filepath.Join(linearRoot, ".kit.yaml"), []byte(`
issues:
    provider: linear
    linear:
        workspace: lsmc
        team_id: add0a7c5-383d-4969-98d4-a5402b4cac66
`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(githubRoot, ".kit.yaml"), []byte("issues:\n    provider: github\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(brokenRoot, ".kit.yaml"), []byte("issues: [\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	cachedLinear := model.ProjectPullRequest{
		ID: "lsmc-bio/labcore#1329", Number: 1329,
		Title: "fix(ENG-67): admit buccal partner orders", HeadRefName: "feature/x",
		UpdatedAt: now,
	}
	cachedUndeployed := model.UndeployedPullRequest{
		Number: 500, Title: "docs(ENG-67): document buccal", HeadRefName: "ENG-67", MergedAt: now,
	}
	cachedGitHub := model.ProjectPullRequest{
		ID: "lsmc-bio/docs#1266", Number: 1266,
		Title: "validate receipts", HeadRefName: "GH-1265", UpdatedAt: now,
	}
	cachedBroken := model.ProjectPullRequest{
		ID: "o/broken#1", Number: 1, Title: "fix(ENG-67): should stay github",
		HeadRefName: "GH-9", UpdatedAt: now,
	}

	scan := scanContext{
		cache: cacheState{
			Projects: map[string]string{},
			Repositories: map[string]cacheEntry{
				"lsmc-bio/labcore": {
					Repository: "lsmc-bio/labcore", ObservedAt: now, CheckedAt: now,
					PullRequests: []model.ProjectPullRequest{cachedLinear},
					Workflows: &model.ProjectWorkflowActivity{Deploys: &model.DeployStatus{
						PullRequests: []model.UndeployedPullRequest{cachedUndeployed},
					}},
				},
				"lsmc-bio/docs": {
					Repository: "lsmc-bio/docs", ObservedAt: now, CheckedAt: now,
					PullRequests: []model.ProjectPullRequest{cachedGitHub},
				},
				"o/broken": {
					Repository: "o/broken", ObservedAt: now, CheckedAt: now,
					PullRequests: []model.ProjectPullRequest{cachedBroken},
				},
			},
		},
		sources: []config.Source{
			{Path: linearRoot}, {Path: githubRoot}, {Path: brokenRoot},
		},
		resolved: map[string]config.Repository{
			filepath.Clean(linearRoot): {Name: "labcore", Path: linearRoot, GitHub: "lsmc-bio/labcore"},
			filepath.Clean(githubRoot): {Name: "docs", Path: githubRoot, GitHub: "lsmc-bio/docs"},
			filepath.Clean(brokenRoot): {Name: "broken", Path: brokenRoot, GitHub: "o/broken"},
		},
		now: now,
	}
	result := buildScanResult(scan, nil, RefreshLocal)
	if len(result.Errors) != 0 || len(result.Warnings) != 0 {
		t.Fatalf("errors %#v warnings %#v", result.Errors, result.Warnings)
	}
	if cachedLinear.IssueLabel != "" || cachedUndeployed.IssueLabel != "" || cachedGitHub.IssueLabel != "" {
		t.Fatal("stamping mutated the cached rows")
	}
	linear := result.Projects[0].PullRequests[0]
	if linear.IssueLabel != "ENG-67" || linear.IssueURL != "https://linear.app/lsmc/issue/ENG-67" {
		t.Fatalf("open linear = %q %q", linear.IssueLabel, linear.IssueURL)
	}
	undeployed := result.Projects[0].Workflows.Deploys.PullRequests[0]
	if undeployed.IssueLabel != "ENG-67" || undeployed.IssueURL != "https://linear.app/lsmc/issue/ENG-67" {
		t.Fatalf("undeployed linear = %q %q", undeployed.IssueLabel, undeployed.IssueURL)
	}
	gh := result.Projects[1].PullRequests[0]
	if gh.IssueLabel != "GH-1265" || gh.IssueURL != "https://github.com/lsmc-bio/docs/issues/1265" {
		t.Fatalf("github = %q %q", gh.IssueLabel, gh.IssueURL)
	}
	broken := result.Projects[2].PullRequests[0]
	if broken.IssueLabel != "GH-9" || broken.IssueURL != "https://github.com/o/broken/issues/9" {
		t.Fatalf("broken kit yaml = %q %q, want the GitHub token only", broken.IssueLabel, broken.IssueURL)
	}
}
