package prindex

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestCommitCountQuerySelectsHistoryTotalCount(t *testing.T) {
	query, aliases := buildCommitCountQuery([]config.Repository{
		{GitHub: "owner/one"}, {GitHub: "owner/two"},
	})
	if !strings.Contains(query, "history(first: 1) { totalCount }") ||
		!strings.Contains(query, "defaultBranchRef") ||
		strings.Contains(query, "pullRequests") ||
		strings.Contains(query, ".github/workflows") {
		t.Fatalf("query = %s", query)
	}
	if len(aliases) != 2 {
		t.Fatalf("aliases = %#v", aliases)
	}
}

func TestHotPullRequestQueryOmitsCommitHistoryTotal(t *testing.T) {
	query, _ := buildQuery([]pageRequest{{
		repository: config.Repository{GitHub: "owner/one"},
	}})
	if strings.Contains(query, "history(first: 1)") {
		t.Fatalf("hot query must not fetch history totals: %s", query)
	}
}

func TestFetchCommitCountsDecodesDefaultBranchHistory(t *testing.T) {
	runner := &graphQLRunner{respond: func(query string, _ int) ([]byte, error) {
		if !strings.Contains(query, "history(first: 1) { totalCount }") {
			t.Fatalf("query = %s", query)
		}
		return responseJSONWithRateLimit(map[string]any{
			"repository0": map[string]any{
				"defaultBranchRef": map[string]any{
					"target": map[string]any{
						"history": map[string]any{"totalCount": 4201},
					},
				},
			},
		}, nil, githubRateLimit(10, 1, 4)), nil
	}}
	result := GitHubClient{Runner: runner}.FetchCommitCounts(
		context.Background(),
		[]config.Repository{{GitHub: "owner/one"}},
	)
	entry := result.Repositories["owner/one"]
	if entry.Error != "" || entry.Count != 4201 || result.RateLimit == nil {
		t.Fatalf("result = %#v", result)
	}
}

func TestCommitCountPolicySkipsFreshGitHubAndThinQuota(t *testing.T) {
	now := time.Date(2026, 9, 13, 16, 0, 0, 0, time.UTC)
	fresh := cacheEntry{
		Repository:            "owner/one",
		CommitCountSource:     commitCountSourceGitHub,
		CommitCountObservedAt: now.Add(-time.Hour),
	}
	if commitCountNeedsGitHub(fresh, now) {
		t.Fatal("fresh github count should wait for the daily cadence")
	}
	stale := cacheEntry{
		Repository:            "owner/one",
		CommitCountSource:     commitCountSourceGitHub,
		CommitCountObservedAt: now.Add(-25 * time.Hour),
	}
	if !commitCountNeedsGitHub(stale, now) {
		t.Fatal("github counts older than 24h should refresh")
	}
	local := cacheEntry{CommitCountSource: commitCountSourceLocal}
	if !commitCountNeedsGitHub(local, now) {
		t.Fatal("local seed should still accept a github overwrite")
	}
	if hasExcessCommitCountQuota(nil, now) {
		t.Fatal("missing quota must not fetch sizes")
	}
	thin := &model.GitHubRateLimit{
		Limit: 5000, Remaining: 1500, ResetAt: now.Add(time.Hour), ObservedAt: now,
	}
	if hasExcessCommitCountQuota(thin, now) {
		t.Fatal("thin remaining must not fetch sizes")
	}
	excess := &model.GitHubRateLimit{
		Limit: 5000, Remaining: 3200, ResetAt: now.Add(time.Hour), ObservedAt: now,
	}
	if !hasExcessCommitCountQuota(excess, now) {
		t.Fatal("excess remaining should allow a daily size fetch")
	}
}
