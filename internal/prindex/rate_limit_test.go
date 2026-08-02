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
		result.RateLimit.BurnRate == nil ||
		result.RateLimit.BurnRate.PointsPerHour != 35 ||
		result.RateLimit.BurnRate.SampleSeconds != 3600 ||
		result.RateLimit.BurnRate.ProjectedExhaustionAt == nil ||
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
		!preserved.RateLimit.ObservedAt.Equal(now.Add(-time.Minute)) ||
		preserved.RateLimit.BurnRate == nil ||
		preserved.RateLimit.BurnRate.PointsPerHour != 35 {
		t.Fatalf("preserved = %#v", preserved.RateLimit)
	}
}

func TestApplyRateLimitBurnRateProjectsExhaustion(t *testing.T) {
	observedAt := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	resetAt := observedAt.Add(time.Hour)
	previous := &model.GitHubRateLimit{
		Limit: 5000, Used: 1000, Remaining: 4000,
		ResetAt: resetAt, ObservedAt: observedAt.Add(-5 * time.Minute),
	}
	current := &model.GitHubRateLimit{
		Limit: 5000, Used: 1500, Remaining: 3500,
		ResetAt: resetAt, ObservedAt: observedAt,
	}
	derived := applyRateLimitBurnRate(current, previous)
	if derived.BurnRate == nil || derived.BurnRate.PointsPerHour != 6000 ||
		derived.BurnRate.SampleSeconds != 300 ||
		derived.BurnRate.ProjectedExhaustionAt == nil ||
		!derived.BurnRate.ProjectedExhaustionAt.Equal(
			observedAt.Add(35*time.Minute),
		) {
		t.Fatalf("derived = %#v", derived)
	}
}

func TestApplyRateLimitBurnRateHandlesZeroAndInvalidSamples(t *testing.T) {
	observedAt := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	resetAt := observedAt.Add(time.Hour)
	base := model.GitHubRateLimit{
		Limit: 5000, Used: 1000, Remaining: 4000,
		ResetAt: resetAt, ObservedAt: observedAt.Add(-5 * time.Minute),
	}
	zero := base
	zero.ObservedAt = observedAt
	derived := applyRateLimitBurnRate(&zero, &base)
	if derived.BurnRate == nil || derived.BurnRate.PointsPerHour != 0 ||
		derived.BurnRate.SampleSeconds != 300 ||
		derived.BurnRate.ProjectedExhaustionAt != nil {
		t.Fatalf("zero burn rate = %#v", derived.BurnRate)
	}

	tests := map[string]func(*model.GitHubRateLimit){
		"new reset window": func(value *model.GitHubRateLimit) {
			value.ResetAt = value.ResetAt.Add(time.Hour)
		},
		"changed limit": func(value *model.GitHubRateLimit) {
			value.Limit = 6000
			value.Remaining = 4900
		},
		"decreased counter": func(value *model.GitHubRateLimit) {
			value.Used = 900
			value.Remaining = 4100
		},
		"short sample": func(value *model.GitHubRateLimit) {
			value.ObservedAt = base.ObservedAt.Add(30 * time.Second)
		},
	}
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			current := base
			current.Used = 1100
			current.Remaining = 3900
			current.ObservedAt = observedAt
			mutate(&current)
			if result := applyRateLimitBurnRate(&current, &base); result.BurnRate != nil {
				t.Fatalf("burn rate = %#v", result.BurnRate)
			}
		})
	}
}

func TestCloneRateLimitCopiesBurnRateProjection(t *testing.T) {
	projected := time.Date(2026, 8, 2, 12, 35, 0, 0, time.UTC)
	source := &model.GitHubRateLimit{BurnRate: &model.GitHubRateLimitBurnRate{
		PointsPerHour: 6000, SampleSeconds: 300,
		ProjectedExhaustionAt: &projected,
	}}
	cloned := cloneRateLimit(source)
	*cloned.BurnRate.ProjectedExhaustionAt = projected.Add(time.Minute)
	if source.BurnRate.ProjectedExhaustionAt.Equal(
		*cloned.BurnRate.ProjectedExhaustionAt,
	) {
		t.Fatal("clone should not share burn-rate projection pointers")
	}
}

func TestCachedBurnRateRejectsInconsistentProjection(t *testing.T) {
	observedAt := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	projected := observedAt.Add(time.Hour)
	value := model.GitHubRateLimit{
		Limit: 5000, Used: 1500, Remaining: 3500,
		ResetAt: observedAt.Add(time.Hour), ObservedAt: observedAt,
		BurnRate: &model.GitHubRateLimitBurnRate{
			PointsPerHour: 6000, SampleSeconds: 300,
			ProjectedExhaustionAt: &projected,
		},
	}
	if validCachedBurnRate(value) {
		t.Fatal("a cached projection inconsistent with remaining capacity should fail closed")
	}
}
