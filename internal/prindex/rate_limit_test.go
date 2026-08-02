package prindex

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestGitHubClientReturnsLastCompleteRateLimit(t *testing.T) {
	runner := &graphQLRunner{respond: func(query string, call int) ([]byte, error) {
		if !strings.Contains(
			query,
			"rateLimit { limit used remaining resetAt cost nodeCount }",
		) {
			t.Fatalf("query omits rate limit metadata: %s", query)
		}
		switch call {
		case 1:
			return responseJSONWithRateLimit(
				map[string]any{"repository0": repositoryPage(1, true, "next")},
				nil, githubRateLimit(101, 3, 12),
			), nil
		case 2:
			return responseJSONWithRateLimit(
				map[string]any{"repository0": repositoryPage(2, false, "")},
				nil, githubRateLimit(103, 2, 4),
			), nil
		default:
			t.Fatalf("unexpected call %d", call)
			return nil, nil
		}
	}}
	result := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	)
	if result.RateLimit == nil || result.RateLimit.Limit != 5000 ||
		result.RateLimit.Used != 103 || result.RateLimit.Remaining != 4897 ||
		result.RateLimit.Cost != 2 || result.RateLimit.NodeCount != 4 ||
		result.RateLimit.ResetAt.Format(time.RFC3339) != "2026-08-02T12:00:00Z" {
		t.Fatalf("rate limit = %#v", result.RateLimit)
	}
}

func TestGitHubClientKeepsLastCompleteRateLimit(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, call int) ([]byte, error) {
		if call == 1 {
			return responseJSONWithRateLimit(
				map[string]any{"repository0": repositoryPage(1, true, "next")},
				nil, githubRateLimit(101, 3, 12),
			), nil
		}
		inconsistent := githubRateLimit(102, 1, 2)
		inconsistent["remaining"] = 4897
		return responseJSONWithRateLimit(
			map[string]any{"repository0": repositoryPage(2, false, "")},
			nil, inconsistent,
		), nil
	}}
	result := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	)
	if result.RateLimit == nil || result.RateLimit.Used != 101 ||
		result.RateLimit.Cost != 3 || len(result.Repositories["owner/one"].PullRequests) != 2 {
		t.Fatalf("result = %#v", result)
	}
}

func TestScannerCachesRateLimitIndependentlyOfRepositoryFailure(t *testing.T) {
	now := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	source := config.Source{Path: "/repo/one"}
	repository := config.Repository{Name: "one", Path: source.Path, GitHub: "owner/one"}
	store := &memoryCacheStore{state: cacheState{
		Version: cacheVersion, Projects: map[string]string{},
		Repositories: map[string]cacheEntry{
			"owner/one": {Repository: repository.GitHub},
		},
		RateLimit: &model.GitHubRateLimit{
			Limit: 5000, Used: 90, Remaining: 4910,
			ResetAt: now.Add(time.Hour), Cost: 1, NodeCount: 1,
			ObservedAt: now.Add(-time.Hour),
		},
	}}
	client := &fakePullRequestClient{
		results: map[string]RepositoryResult{
			"owner/one": {Error: "repository unavailable"},
		},
		rateLimit: &GitHubRateLimit{
			Limit: 5000, Used: 125, Remaining: 4875,
			ResetAt: now.Add(time.Hour), Cost: 4, NodeCount: 12,
		},
	}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{
			Repositories: []config.Repository{repository},
		}},
		Client: client, Store: store, Now: func() time.Time { return now },
	}
	result, err := scanner.Scan(
		context.Background(), config.Config{Projects: []config.Source{source}}, RefreshForce,
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.RateLimit == nil || result.RateLimit.Used != 125 ||
		result.RateLimit.Cost != 4 || !result.RateLimit.ObservedAt.Equal(now) ||
		result.Projects[0].Status != model.ProjectPullRequestsUnavailable {
		t.Fatalf("result = %#v", result)
	}

	client.rateLimit = nil
	now = now.Add(time.Minute)
	preserved, err := scanner.Scan(
		context.Background(), config.Config{Projects: []config.Source{source}}, RefreshForce,
	)
	if err != nil {
		t.Fatal(err)
	}
	if preserved.RateLimit == nil || preserved.RateLimit.Used != 125 ||
		!preserved.RateLimit.ObservedAt.Equal(now.Add(-time.Minute)) {
		t.Fatalf("preserved = %#v", preserved.RateLimit)
	}
}
