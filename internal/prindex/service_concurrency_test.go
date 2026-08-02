package prindex

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestScannerReturnsCacheSnapshotMutatedUnderStoreLock(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	one := config.Repository{Name: "one", Path: "/repo/one", GitHub: "owner/one"}
	two := config.Repository{Name: "two", Path: "/repo/two", GitHub: "owner/two"}
	store := &memoryCacheStore{state: cacheState{
		Version: cacheVersion, Projects: map[string]string{},
		Repositories: map[string]cacheEntry{
			"owner/one": {Repository: one.GitHub, ObservedAt: now.Add(-6 * time.Minute)},
			"owner/two": {
				Repository: two.GitHub, ObservedAt: now.Add(-time.Minute),
				PullRequests: []model.ProjectPullRequest{{
					ID: "owner/two#2", Number: 2, Title: "Before",
					HeadRefName: "GH-2",
				}},
			},
		},
	}}
	store.beforeUpdate = func(state *cacheState) {
		entry := state.Repositories["owner/two"]
		entry.PullRequests[0].Title = "Concurrent"
		state.Repositories["owner/two"] = entry
	}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{one, two},
		}},
		Client: &fakePullRequestClient{results: map[string]RepositoryResult{
			"owner/one": {PullRequests: []model.ProjectPullRequest{}},
		}},
		Store: store, Now: func() time.Time { return now },
	}
	result, err := scanner.Scan(context.Background(), config.Config{
		Projects: []config.Source{{Path: one.Path}, {Path: two.Path}},
	}, RefreshStale)
	if err != nil {
		t.Fatal(err)
	}
	if result.Projects[1].PullRequests[0].Title != "Concurrent" {
		t.Fatalf("result = %#v", result.Projects[1])
	}
}

func cloneCache(source cacheState) cacheState {
	cloned := emptyCache()
	cloned.UpdatedAt = source.UpdatedAt
	cloned.RateLimit = cloneRateLimit(source.RateLimit)
	for path, repository := range source.Projects {
		cloned.Projects[filepath.Clean(path)] = repository
	}
	for key, entry := range source.Repositories {
		entry.PullRequests = append(
			[]model.ProjectPullRequest(nil), entry.PullRequests...,
		)
		cloned.Repositories[key] = entry
	}
	return cloned
}
