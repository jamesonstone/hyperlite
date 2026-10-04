package prindex

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

var budgetNow = time.Date(2026, 10, 4, 12, 0, 0, 0, time.UTC)

func reusableEntry(updatedAt time.Time, ci string) cacheEntry {
	threads := 0
	return cacheEntry{
		Repository:      "owner/one",
		DetailCheckedAt: budgetNow.Add(-5 * time.Minute),
		PullRequests: []model.ProjectPullRequest{{
			ID: "owner/one#1", Number: 1, HeadRefName: "GH-1", HeadRefOID: "head-1",
			UnresolvedReviewThreads: &threads, CIState: ci, UpdatedAt: updatedAt,
		}},
		Workflows: &model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{
			{Scope: model.WorkflowRunScopePullRequest, PullRequestNumber: 1},
			{Scope: model.WorkflowRunScopeTip},
		}},
	}
}

func TestListingHintEligibility(t *testing.T) {
	updated := budgetNow.Add(-time.Hour)
	hint, ok := listingHint(reusableEntry(updated, "success"), budgetNow)
	if !ok || hint.OpenCount != 1 || !hint.LatestUpdatedAt.Equal(updated) || len(hint.PullRequestRuns) != 1 {
		t.Fatalf("hint=%#v ok=%v", hint, ok)
	}
	old := reusableEntry(updated, "success")
	old.DetailCheckedAt = budgetNow.Add(-detailReuseWindow)
	failed := reusableEntry(updated, "success")
	failed.LastError = "boom"
	for name, entry := range map[string]cacheEntry{
		"pending ci":    reusableEntry(updated, "pending"),
		"stale details": old,
		"last error":    failed,
		"never read":    {Repository: "owner/one"},
	} {
		if _, ok := listingHint(entry, budgetNow); ok {
			t.Errorf("%s should not be reusable", name)
		}
	}
}

func probeWithLatest(count int, latest time.Time) func(string) ([]byte, error) {
	return func(string) ([]byte, error) {
		return responseJSON(map[string]any{"repository0": map[string]any{
			"openPullRequests": map[string]any{
				"totalCount": count,
				"nodes":      []map[string]any{{"updatedAt": latest.Format(time.RFC3339)}},
			},
		}}, nil), nil
	}
}

func TestProbeReusesUnchangedDetailsAndRereadsChangedOnes(t *testing.T) {
	updated := budgetNow.Add(-time.Hour)
	hint, _ := listingHint(reusableEntry(updated, "success"), budgetNow)
	hints := map[string]ListingHint{"owner/one": hint}
	repositories := []config.Repository{{GitHub: "owner/one"}}

	unchanged := &graphQLRunner{probe: probeWithLatest(1, updated), respond: func(string, int) ([]byte, error) {
		return nil, errors.New("detail query must be skipped")
	}}
	got := (GitHubClient{Runner: unchanged}).ListOpenReusing(context.Background(), repositories, hints).Repositories["owner/one"]
	if unchanged.calls != 0 || !got.Reused || got.Error != "" || len(got.PullRequests) != 1 ||
		got.Activity == nil || len(got.Activity.PullRequestRuns) != 1 {
		t.Fatalf("calls=%d result=%#v", unchanged.calls, got)
	}

	changed := &graphQLRunner{probe: probeWithLatest(1, updated.Add(time.Minute)), respond: func(query string, _ int) ([]byte, error) {
		return echoRepositoryPages(query), nil
	}}
	got = (GitHubClient{Runner: changed}).ListOpenReusing(context.Background(), repositories, hints).Repositories["owner/one"]
	if changed.calls != 1 || got.Reused || got.Error != "" {
		t.Fatalf("calls=%d result=%#v", changed.calls, got)
	}
}

func TestAutomaticRefreshPausesBelowQuotaFloor(t *testing.T) {
	low := &model.GitHubRateLimit{
		Limit: 5000, Remaining: 900, ResetAt: budgetNow.Add(20 * time.Minute), ObservedAt: budgetNow.Add(-time.Minute),
	}
	if message := automaticRefreshPause(low, RefreshStale, budgetNow); !strings.Contains(message, "900") {
		t.Fatalf("message = %q", message)
	}
	if automaticRefreshPause(low, RefreshForce, budgetNow) != "" {
		t.Fatal("explicit refresh must never pause")
	}
	if automaticRefreshPause(low, RefreshStale, budgetNow.Add(21*time.Minute)) != "" {
		t.Fatal("a reset window must not pause")
	}
	healthy := *low
	healthy.Remaining = 1000
	if automaticRefreshPause(&healthy, RefreshStale, budgetNow) != "" {
		t.Fatal("remaining at the floor must not pause")
	}
}

func TestScannerSkipsGitHubWhenAutomaticRefreshIsPaused(t *testing.T) {
	source := config.Source{Path: "/repo/one"}
	repository := config.Repository{Name: "one", Path: source.Path, GitHub: "owner/one"}
	store := &memoryCacheStore{state: cacheState{
		Version: cacheVersion, Projects: map[string]string{source.Path: repository.GitHub},
		Repositories: map[string]cacheEntry{"owner/one": reusableEntry(budgetNow.Add(-time.Hour), "success")},
		RateLimit: &model.GitHubRateLimit{
			Limit: 5000, Remaining: 10, ResetAt: budgetNow.Add(time.Hour), ObservedAt: budgetNow,
		},
	}}
	client := &fakePullRequestClient{}
	scanner := Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{Repositories: []config.Repository{repository}}},
		Client:    client, Store: store, Now: func() time.Time { return budgetNow },
	}
	result, err := scanner.Scan(context.Background(), config.Config{Projects: []config.Source{source}}, RefreshStale)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 0 || len(result.Warnings) != 1 || result.Warnings[0].Stage != "pull-request-quota" {
		t.Fatalf("calls=%d warnings=%#v", client.calls, result.Warnings)
	}
	if _, err := scanner.Scan(context.Background(), config.Config{Projects: []config.Source{source}}, RefreshForce); err != nil {
		t.Fatal(err)
	}
	if client.calls != 1 || client.hints[0] != nil {
		t.Fatalf("forced refresh calls=%d hints=%#v", client.calls, client.hints)
	}
}
