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
					HeadRefOID:              "head-1",
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

func TestScannerRefreshesLegacyProjectionFieldsInsideFiveMinuteFloor(t *testing.T) {
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
			HeadRefOID:              "head-1",
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
		result.Projects[0].PullRequests[0].HeadRefOID != "head-1" ||
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
						HeadRefOID:  "head-1",
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
	pullRequests := result.Projects[0].PullRequests
	if client.calls != 0 ||
		result.Projects[0].Status != model.ProjectPullRequestsCached ||
		result.Projects[0].Message != "review pagination failed" ||
		len(pullRequests) != 1 ||
		pullRequests[0].ID != "owner/one#1" ||
		pullRequests[0].UnresolvedReviewThreads != nil {
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
