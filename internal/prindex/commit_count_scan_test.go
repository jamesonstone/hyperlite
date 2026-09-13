package prindex

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

type fakeCommitCountClient struct {
	calls        int
	repositories [][]config.Repository
	result       CommitCountResult
}

func (f *fakeCommitCountClient) FetchCommitCounts(
	_ context.Context,
	repositories []config.Repository,
) CommitCountResult {
	f.calls++
	f.repositories = append(
		f.repositories, append([]config.Repository(nil), repositories...),
	)
	return f.result
}

type fakeGitCountRunner struct {
	counts map[string]string
}

func (f fakeGitCountRunner) Run(
	_ context.Context,
	dir, name string,
	args ...string,
) ([]byte, error) {
	if name != "git" || len(args) != 3 || args[0] != "rev-list" ||
		args[1] != "--count" || args[2] != "HEAD" {
		return nil, fmt.Errorf("unexpected git command %s %v in %s", name, args, dir)
	}
	count, ok := f.counts[dir]
	if !ok {
		return nil, fmt.Errorf("no local count for %s", dir)
	}
	return []byte(count), nil
}

func TestRefreshCommitCountsSeedsLocalAndFetchesStaleGitHub(t *testing.T) {
	now := time.Date(2026, 9, 13, 16, 0, 0, 0, time.UTC)
	source := config.Source{Path: "/repo/one"}
	repository := config.Repository{Name: "one", Path: source.Path, GitHub: "owner/one"}
	threads := 0
	store := &memoryCacheStore{state: cacheState{
		Version:  cacheVersion,
		Projects: map[string]string{source.Path: repository.GitHub},
		RateLimit: &model.GitHubRateLimit{
			Limit: 5000, Remaining: 4000, ResetAt: now.Add(time.Hour), ObservedAt: now,
		},
		Repositories: map[string]cacheEntry{
			"owner/one": {
				Repository: repository.GitHub, ObservedAt: now.Add(-time.Minute),
				PullRequests: []model.ProjectPullRequest{{
					ID: "owner/one#1", Number: 1, Title: "Open",
					HeadRefName: "GH-1", HeadRefOID: "head-1",
					UnresolvedReviewThreads: &threads,
				}},
				Workflows: &model.ProjectWorkflowActivity{},
			},
		},
	}}
	sizes := &fakeCommitCountClient{result: CommitCountResult{
		Repositories: map[string]CommitCountEntry{"owner/one": {Count: 9001}},
	}}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{repository},
		}},
		Client: &fakePullRequestClient{results: map[string]RepositoryResult{}},
		Store:  store,
		Sizes:  sizes,
		Git:    fakeGitCountRunner{counts: map[string]string{source.Path: "12"}},
		Now:    func() time.Time { return now },
	}
	scan, err := scanner.Scan(context.Background(), config.Config{
		Projects: []config.Source{source},
	}, RefreshForce)
	if err != nil {
		t.Fatal(err)
	}
	if sizes.calls != 1 || scan.Projects[0].CommitCount == nil ||
		*scan.Projects[0].CommitCount != 9001 {
		t.Fatalf("scan=%#v sizes=%#v cache=%#v", scan.Projects[0], sizes, store.state)
	}
	entry := store.state.Repositories["owner/one"]
	if entry.CommitCountSource != commitCountSourceGitHub ||
		entry.CommitCount == nil || *entry.CommitCount != 9001 {
		t.Fatalf("cache entry = %#v", entry)
	}
}

func TestRefreshCommitCountsKeepsLocalWhenQuotaIsThin(t *testing.T) {
	now := time.Date(2026, 9, 13, 16, 0, 0, 0, time.UTC)
	source := config.Source{Path: "/repo/one"}
	repository := config.Repository{Name: "one", Path: source.Path, GitHub: "owner/one"}
	store := &memoryCacheStore{state: cacheState{
		Version:  cacheVersion,
		Projects: map[string]string{source.Path: repository.GitHub},
		RateLimit: &model.GitHubRateLimit{
			Limit: 5000, Remaining: 800, ResetAt: now.Add(time.Hour), ObservedAt: now,
		},
		Repositories: map[string]cacheEntry{
			"owner/one": {Repository: repository.GitHub, ObservedAt: now},
		},
	}}
	sizes := &fakeCommitCountClient{result: CommitCountResult{
		Repositories: map[string]CommitCountEntry{"owner/one": {Count: 9001}},
	}}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{repository},
		}},
		Store: store,
		Sizes: sizes,
		Git:   fakeGitCountRunner{counts: map[string]string{source.Path: "44"}},
		Now:   func() time.Time { return now },
	}
	scan, err := scanner.Scan(context.Background(), config.Config{
		Projects: []config.Source{source},
	}, RefreshLocal)
	if err != nil {
		t.Fatal(err)
	}
	if sizes.calls != 0 || scan.Projects[0].CommitCount == nil ||
		*scan.Projects[0].CommitCount != 44 {
		t.Fatalf("scan=%#v sizes=%d", scan.Projects[0], sizes.calls)
	}
	if store.state.Repositories["owner/one"].CommitCountSource != commitCountSourceLocal {
		t.Fatalf("source = %q", store.state.Repositories["owner/one"].CommitCountSource)
	}
}

func TestApplyCommitCountsPreservesPreviousOnError(t *testing.T) {
	now := time.Date(2026, 9, 13, 16, 0, 0, 0, time.UTC)
	count := 12
	cache := cacheState{Repositories: map[string]cacheEntry{
		"owner/one": {
			Repository: "owner/one", CommitCount: &count,
			CommitCountSource: commitCountSourceLocal,
		},
	}}
	changed := applyCommitCounts(&cache, CommitCountResult{
		Repositories: map[string]CommitCountEntry{
			"owner/one": {Error: "boom"},
		},
	}, now)
	if changed || cache.Repositories["owner/one"].CommitCount == nil ||
		*cache.Repositories["owner/one"].CommitCount != 12 {
		t.Fatalf("cache = %#v changed=%v", cache, changed)
	}
}
