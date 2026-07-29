package workscan

import (
	"context"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/threadstate"
)

func TestProjectIndexEntryUsesRealRegisteredPathsInStableOrder(t *testing.T) {
	repository := config.Repository{
		Name: "hyperlite", Path: "/repo/hyperlite",
		GitHub: "owner/hyperlite", Base: "main",
	}
	entry := projectIndexEntry(repository, []gitscan.LocalLane{
		localLane("GH-9", model.PublicationPublished, model.Worktree{
			Path: "/worktrees/hyperlite/GH-9",
		}),
		localLane("GH-7", model.PublicationPublished, model.Worktree{
			Path: "/worktrees/hyperlite/GH-7",
		}),
		localLane("main", model.PublicationBase, model.Worktree{
			Path: "/repo/hyperlite",
		}),
		localLane("stale", model.PublicationUnknown, model.Worktree{
			Path: "/missing/hyperlite/stale", Prunable: true,
		}),
	})

	if entry.ID != repository.Path || entry.Repository != repository.GitHub ||
		len(entry.Lanes) != 3 {
		t.Fatalf("entry = %#v", entry)
	}
	if !entry.Lanes[0].Primary || entry.Lanes[0].Branch != "main" ||
		entry.Lanes[1].Branch != "GH-7" || entry.Lanes[2].Branch != "GH-9" {
		t.Fatalf("lanes = %#v", entry.Lanes)
	}
}

func TestProjectIndexPreservesConfiguredOrderAndMissingPaths(t *testing.T) {
	cfg := config.Config{Projects: []config.Source{
		{Path: "/configured/zeta"},
		{Path: "/configured/alpha"},
	}}
	results := []repositoryResult{{
		project: model.ProjectIndexEntry{
			ID: "/configured/alpha", Name: "alpha", Path: "/configured/alpha",
			Repository: "owner/alpha",
			Lanes: []model.ProjectLane{{
				ID: "/configured/alpha", Path: "/configured/alpha", Primary: true,
			}},
		},
	}}

	index := buildProjectIndex(cfg, results, nil)
	if len(index) != 2 || index[0].Name != "zeta" ||
		index[0].Path != "/configured/zeta" || index[0].Repository != "" ||
		index[1].Repository != "owner/alpha" {
		t.Fatalf("index = %#v", index)
	}
}

func TestProjectIndexShowsOnlyActiveExactWorktreeLanes(t *testing.T) {
	entry := model.ProjectIndexEntry{
		ID: "/repo/kit", Name: "kit", Path: "/repo/kit",
		Repository: "owner/kit",
		Lanes: []model.ProjectLane{
			{ID: "/repo/kit", Path: "/repo/kit", Primary: true},
			{ID: "/worktrees/kit/GH-7", Path: "/worktrees/kit/GH-7"},
			{ID: "/worktrees/kit/GH-8", Path: "/worktrees/kit/GH-8"},
		},
	}
	threads := []model.Thread{
		{
			ID: "active", Active: true, Repositories: []string{"owner/kit"},
			Artifacts: []model.ThreadArtifact{{
				Kind: model.ArtifactWorktree, Path: "/worktrees/kit/GH-7",
			}},
		},
		{
			ID: "dormant", Active: false, Repositories: []string{"owner/kit"},
			Artifacts: []model.ThreadArtifact{{
				Kind: model.ArtifactWorktree, Path: "/worktrees/kit/GH-8",
			}},
		},
	}

	index := buildProjectIndex(
		config.Config{},
		[]repositoryResult{{project: entry}},
		threads,
	)
	if len(index) != 1 || len(index[0].Lanes) != 2 ||
		index[0].Lanes[1].Path != "/worktrees/kit/GH-7" {
		t.Fatalf("index = %#v", index)
	}
}

func TestScanBuildsProjectIndexWithoutAdditionalGitScans(t *testing.T) {
	now := time.Date(2026, 7, 29, 12, 0, 0, 0, time.UTC)
	repository := config.Repository{
		Name: "hyperlite", Path: "/repo/hyperlite",
		GitHub: "owner/hyperlite", Base: "main", Remote: "origin",
	}
	git := &countingProjectGit{result: gitscan.Result{Lanes: []gitscan.LocalLane{
		localLane("main", model.PublicationBase, model.Worktree{
			Path: repository.Path, UpdatedAt: now,
		}),
	}}}
	github := &countingProjectGitHub{}
	scanner := testScanner(
		now, []config.Repository{repository}, github, fakeMemory{},
		&fakeStore{state: threadstate.Empty()},
	)
	scanner.Git = git
	cfg := testConfig()
	cfg.Projects = []config.Source{{Path: repository.Path}}

	result, err := scanner.Scan(context.Background(), cfg, false, false)
	if err != nil {
		t.Fatal(err)
	}
	if git.calls != 1 || github.calls != 1 || len(result.ProjectIndex) != 1 ||
		result.ProjectIndex[0].Path != repository.Path ||
		len(result.Threads) != 0 {
		t.Fatalf("git=%d github=%d result=%#v", git.calls, github.calls, result)
	}
}

func TestScanKeepsConfiguredProjectWhenDiscoveryFails(t *testing.T) {
	scanner := testScanner(
		time.Now(), nil, fakeGitHub{}, fakeMemory{},
		&fakeStore{state: threadstate.Empty()},
	)
	cfg := testConfig()
	cfg.Projects = []config.Source{{Path: "/configured/unavailable"}}

	result, err := scanner.ScanLocal(context.Background(), cfg, false)
	if err != nil {
		t.Fatal(err)
	}
	if result.Summary.Projects != 1 || len(result.ProjectIndex) != 1 ||
		result.ProjectIndex[0].Path != "/configured/unavailable" {
		t.Fatalf("result = %#v", result)
	}
}

type countingProjectGit struct {
	calls  int
	result gitscan.Result
}

type countingProjectGitHub struct {
	calls int
}

func (f *countingProjectGitHub) CollectRepository(
	context.Context,
	config.Repository,
	string,
	string,
	[]int,
) model.RemoteEvidence {
	f.calls++
	return emptyRemote()
}

func (f *countingProjectGit) Scan(
	context.Context,
	config.Repository,
	bool,
	time.Duration,
) gitscan.Result {
	f.calls++
	return f.result
}
