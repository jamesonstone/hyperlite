package prindex

import (
	"context"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestScannerHonorsFiveMinuteFloorAndForceRefresh(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	cachedReviewThreads := 0
	source := config.Source{Path: "/repo/one"}
	repository := config.Repository{Name: "one", Path: source.Path, GitHub: "owner/one"}
	store := &memoryCacheStore{state: cacheState{
		Version:  cacheVersion,
		Projects: map[string]string{source.Path: repository.GitHub},
		Repositories: map[string]cacheEntry{
			"owner/one": {
				Repository: repository.GitHub,
				ObservedAt: now.Add(-4 * time.Minute),
				PullRequests: []model.ProjectPullRequest{{
					ID: "owner/one#1", Number: 1, Title: "Cached",
					HeadRefName:             "GH-1",
					UnresolvedReviewThreads: &cachedReviewThreads,
				}},
			},
		},
	}}
	client := &fakePullRequestClient{results: map[string]RepositoryResult{
		"owner/one": {PullRequests: []model.ProjectPullRequest{{
			ID: "owner/one#2", Number: 2, Title: "Fresh",
		}}},
	}}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{repository},
		}},
		Client: client, Store: store, Now: func() time.Time { return now },
	}
	cfg := config.Config{Projects: []config.Source{source}}

	current, err := scanner.Scan(context.Background(), cfg, RefreshStale)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 0 || current.Projects[0].PullRequests[0].Number != 1 ||
		current.Projects[0].Status != model.ProjectPullRequestsCurrent {
		t.Fatalf("calls=%d current=%#v", client.calls, current)
	}

	forced, err := scanner.Scan(context.Background(), cfg, RefreshForce)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 1 || forced.Projects[0].PullRequests[0].Number != 2 ||
		forced.Projects[0].Status != model.ProjectPullRequestsCurrent ||
		forced.Projects[0].ObservedAt == nil ||
		!forced.Projects[0].ObservedAt.Equal(now) {
		t.Fatalf("calls=%d forced=%#v", client.calls, forced)
	}
}

func TestScannerRefreshesLegacyReviewCountsInsideFiveMinuteFloor(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	freshReviewThreads := 0
	source := config.Source{Path: "/repo/one"}
	repository := config.Repository{Name: "one", Path: source.Path, GitHub: "owner/one"}
	store := &memoryCacheStore{state: cacheState{
		Version:  cacheVersion,
		Projects: map[string]string{source.Path: repository.GitHub},
		Repositories: map[string]cacheEntry{
			"owner/one": {
				Repository: repository.GitHub,
				CheckedAt:  now.Add(-time.Minute),
				ObservedAt: now.Add(-time.Minute),
				PullRequests: []model.ProjectPullRequest{{
					ID: "owner/one#1", Number: 1, Title: "Legacy",
					HeadRefName: "GH-1",
				}},
			},
		},
	}}
	client := &fakePullRequestClient{results: map[string]RepositoryResult{
		"owner/one": {PullRequests: []model.ProjectPullRequest{{
			ID: "owner/one#1", Number: 1, Title: "Fresh",
			HeadRefName:             "GH-1",
			UnresolvedReviewThreads: &freshReviewThreads,
		}}},
	}}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{repository},
		}},
		Client: client, Store: store, Now: func() time.Time { return now },
	}
	result, err := scanner.Scan(
		context.Background(),
		config.Config{Projects: []config.Source{source}},
		RefreshStale,
	)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 1 ||
		result.Projects[0].PullRequests[0].UnresolvedReviewThreads == nil ||
		*result.Projects[0].PullRequests[0].UnresolvedReviewThreads != 0 {
		t.Fatalf("calls=%d result=%#v", client.calls, result)
	}
}

func TestScannerThrottlesFailedLegacyReviewCountHydration(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	source := config.Source{Path: "/repo/one"}
	repository := config.Repository{Name: "one", Path: source.Path, GitHub: "owner/one"}
	client := &fakePullRequestClient{}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{repository},
		}},
		Client: client,
		Store: &memoryCacheStore{state: cacheState{
			Version:  cacheVersion,
			Projects: map[string]string{source.Path: repository.GitHub},
			Repositories: map[string]cacheEntry{
				"owner/one": {
					Repository: repository.GitHub,
					CheckedAt:  now.Add(-time.Minute),
					ObservedAt: now.Add(-time.Minute),
					LastError:  "review pagination failed",
					PullRequests: []model.ProjectPullRequest{{
						ID: "owner/one#1", Number: 1, Title: "Legacy",
						HeadRefName: "GH-1",
					}},
				},
			},
		}},
		Now: func() time.Time { return now },
	}
	result, err := scanner.Scan(
		context.Background(),
		config.Config{Projects: []config.Source{source}},
		RefreshStale,
	)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 0 ||
		result.Projects[0].Status != model.ProjectPullRequestsCached ||
		result.Projects[0].Message != "review pagination failed" {
		t.Fatalf("calls=%d result=%#v", client.calls, result)
	}
}

func TestScannerRefreshesOnlyStaleRepositoriesInOneClientCall(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	one := config.Repository{Name: "one", Path: "/repo/one", GitHub: "owner/one"}
	two := config.Repository{Name: "two", Path: "/repo/two", GitHub: "owner/two"}
	store := &memoryCacheStore{state: cacheState{
		Version: cacheVersion, Projects: map[string]string{},
		Repositories: map[string]cacheEntry{
			"owner/one": {Repository: one.GitHub, ObservedAt: now.Add(-6 * time.Minute)},
			"owner/two": {Repository: two.GitHub, ObservedAt: now.Add(-time.Minute)},
		},
	}}
	client := &fakePullRequestClient{results: map[string]RepositoryResult{
		"owner/one": {PullRequests: []model.ProjectPullRequest{}},
	}}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{one, two},
		}},
		Client: client, Store: store, Now: func() time.Time { return now },
	}
	result, err := scanner.Scan(context.Background(), config.Config{
		Projects: []config.Source{{Path: one.Path}, {Path: two.Path}},
	}, RefreshStale)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 1 || len(client.repositories) != 1 ||
		len(client.repositories[0]) != 1 ||
		client.repositories[0][0].GitHub != one.GitHub {
		t.Fatalf("calls=%d repositories=%#v", client.calls, client.repositories)
	}
	if result.Projects[0].Status != model.ProjectPullRequestsCurrent ||
		result.Projects[1].Status != model.ProjectPullRequestsCurrent {
		t.Fatalf("result = %#v", result)
	}
}

func TestScannerPreservesCachedRowsAndMarksUnavailableProjects(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	cachedReviewThreads := 2
	partialReviewThreads := 99
	cached := config.Repository{Name: "cached", Path: "/repo/cached", GitHub: "owner/cached"}
	missing := config.Repository{Name: "missing", Path: "/repo/missing", GitHub: "owner/missing"}
	unresolvedPath := "/repo/local-only"
	store := &memoryCacheStore{state: cacheState{
		Version: cacheVersion,
		Projects: map[string]string{
			cached.Path:    cached.GitHub,
			unresolvedPath: "owner/previous",
		},
		Repositories: map[string]cacheEntry{
			"owner/cached": {
				Repository: cached.GitHub, ObservedAt: now.Add(-time.Hour),
				PullRequests: []model.ProjectPullRequest{{
					ID: "owner/cached#7", Number: 7, Title: "Retained",
					UnresolvedReviewThreads: &cachedReviewThreads,
				}},
			},
			"owner/previous": {
				Repository: "owner/previous", ObservedAt: now.Add(-time.Hour),
				PullRequests: []model.ProjectPullRequest{{
					ID: "owner/previous#8", Number: 8, Title: "Previous",
				}},
			},
		},
	}}
	client := &fakePullRequestClient{results: map[string]RepositoryResult{
		"owner/cached": {
			PullRequests: []model.ProjectPullRequest{{
				ID: "owner/cached#7", Number: 7, Title: "Partial",
				UnresolvedReviewThreads: &partialReviewThreads,
			}},
			Error: "review pagination failed",
		},
		"owner/missing": {Error: "repository unavailable"},
	}}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{cached, missing},
			Warnings: []discovery.Warning{{
				Path: unresolvedPath, Stage: "inspect", Message: "no GitHub remote found",
			}},
		}},
		Client: client, Store: store, Now: func() time.Time { return now },
	}
	result, err := scanner.Scan(context.Background(), config.Config{
		Projects: []config.Source{
			{Path: cached.Path}, {Path: missing.Path}, {Path: unresolvedPath},
		},
	}, RefreshStale)
	if err != nil {
		t.Fatal(err)
	}
	if result.Projects[0].Status != model.ProjectPullRequestsCached ||
		len(result.Projects[0].PullRequests) != 1 ||
		result.Projects[0].Message != "review pagination failed" ||
		result.Projects[0].PullRequests[0].UnresolvedReviewThreads == nil ||
		*result.Projects[0].PullRequests[0].UnresolvedReviewThreads != 2 {
		t.Fatalf("cached project = %#v", result.Projects[0])
	}
	if result.Projects[1].Status != model.ProjectPullRequestsUnavailable ||
		result.Projects[1].Message != "repository unavailable" {
		t.Fatalf("missing project = %#v", result.Projects[1])
	}
	if result.Projects[2].Status != model.ProjectPullRequestsCached ||
		len(result.Projects[2].PullRequests) != 1 ||
		result.Projects[2].Message != "no GitHub remote found" {
		t.Fatalf("unresolved project = %#v", result.Projects[2])
	}
	retried, err := scanner.Scan(context.Background(), config.Config{
		Projects: []config.Source{
			{Path: cached.Path}, {Path: missing.Path}, {Path: unresolvedPath},
		},
	}, RefreshStale)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 1 || retried.CheckedAt == nil || !retried.CheckedAt.Equal(now) ||
		retried.Projects[0].Message != "review pagination failed" {
		t.Fatalf("calls=%d retried=%#v", client.calls, retried)
	}
}

func TestScannerLocalModeNeverCallsGitHubAndReportsStaleCache(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	repository := config.Repository{Name: "one", Path: "/repo/one", GitHub: "owner/one"}
	client := &fakePullRequestClient{}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{repository},
		}},
		Client: client,
		Store: &memoryCacheStore{state: cacheState{
			Version: cacheVersion, Projects: map[string]string{},
			Repositories: map[string]cacheEntry{
				"owner/one": {
					Repository: repository.GitHub,
					ObservedAt: now.Add(-RefreshInterval),
				},
			},
		}},
		Now: func() time.Time { return now },
	}
	result, err := scanner.Scan(context.Background(), config.Config{
		Projects: []config.Source{{Path: repository.Path}},
	}, RefreshLocal)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 0 ||
		result.Projects[0].Status != model.ProjectPullRequestsCached ||
		result.Projects[0].Message != "Cached pull request data is older than five minutes" {
		t.Fatalf("calls=%d result=%#v", client.calls, result)
	}
}

func TestScannerLocalModeRequiresEveryResolvedProjectCheck(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	one := config.Repository{Name: "one", Path: "/repo/one", GitHub: "owner/one"}
	two := config.Repository{Name: "two", Path: "/repo/two", GitHub: "owner/two"}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{one, two},
		}},
		Store: &memoryCacheStore{state: cacheState{
			Version: cacheVersion, Projects: map[string]string{},
			Repositories: map[string]cacheEntry{
				"owner/one": {
					Repository: one.GitHub, CheckedAt: now,
					ObservedAt: now, PullRequests: []model.ProjectPullRequest{},
				},
			},
		}},
		Now: func() time.Time { return now },
	}
	result, err := scanner.Scan(context.Background(), config.Config{
		Projects: []config.Source{{Path: one.Path}, {Path: two.Path}},
	}, RefreshLocal)
	if err != nil {
		t.Fatal(err)
	}
	if result.CheckedAt != nil ||
		result.Projects[1].Status != model.ProjectPullRequestsUnavailable {
		t.Fatalf("result = %#v", result)
	}
}

type fakeProjectDiscoverer struct {
	result discovery.Result
}

func (f fakeProjectDiscoverer) Discover(
	context.Context,
	[]config.Source,
) discovery.Result {
	return f.result
}

type fakePullRequestClient struct {
	calls        int
	repositories [][]config.Repository
	results      map[string]RepositoryResult
}

func (f *fakePullRequestClient) ListOpen(
	_ context.Context,
	repositories []config.Repository,
) map[string]RepositoryResult {
	f.calls++
	f.repositories = append(
		f.repositories, append([]config.Repository(nil), repositories...),
	)
	return f.results
}

type memoryCacheStore struct {
	state        cacheState
	warning      string
	beforeUpdate func(*cacheState)
}

func (s *memoryCacheStore) Load() (cacheState, string, error) {
	return cloneCache(s.state), s.warning, nil
}

func (s *memoryCacheStore) Update(mutate func(*cacheState)) (cacheState, error) {
	state := cloneCache(s.state)
	if s.beforeUpdate != nil {
		s.beforeUpdate(&state)
	}
	mutate(&state)
	s.state = state
	return cloneCache(state), nil
}
