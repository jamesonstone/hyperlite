package prindex

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestGitHubClientStopsOnRepeatedPaginationCursor(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		return responseJSON(map[string]any{
			"repository0": repositoryPage(1, true, "same-cursor"),
		}, nil), nil
	}}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	).Repositories
	if runner.calls != 2 ||
		!strings.Contains(results["owner/one"].Error, "cursor repeated") {
		t.Fatalf("calls=%d result=%#v", runner.calls, results["owner/one"])
	}
}

func TestGitHubClientStopsAtPaginationPageLimit(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, call int) ([]byte, error) {
		return responseJSON(map[string]any{
			"repository0": repositoryPage(call, true, fmt.Sprintf("cursor-%d", call)),
		}, nil), nil
	}}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	).Repositories
	if runner.calls != maxRepositoryPages ||
		!strings.Contains(results["owner/one"].Error, "pagination exceeded") {
		t.Fatalf("calls=%d result=%#v", runner.calls, results["owner/one"])
	}
}

func TestGitHubClientStopsOnRepeatedReviewThreadCursor(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, call int) ([]byte, error) {
		if call == 1 {
			return responseJSON(map[string]any{
				"repository0": repositoryPageWithReviewThreads(
					1, false, "", nil, true, "same-review-cursor",
				),
			}, nil), nil
		}
		return responseJSON(map[string]any{
			"repository0": reviewThreadRepositoryPage(
				nil, true, "same-review-cursor",
			),
		}, nil), nil
	}}
	result := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	).Repositories["owner/one"]
	if runner.calls != 2 || !strings.Contains(result.Error, "cursor repeated") {
		t.Fatalf("calls=%d result=%#v", runner.calls, result)
	}
}

func TestGitHubClientStopsAtReviewThreadPageLimit(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, call int) ([]byte, error) {
		if call == 1 {
			return responseJSON(map[string]any{
				"repository0": repositoryPageWithReviewThreads(
					1, false, "", nil, true, "review-cursor-1",
				),
			}, nil), nil
		}
		return responseJSON(map[string]any{
			"repository0": reviewThreadRepositoryPage(
				nil, true, fmt.Sprintf("review-cursor-%d", call),
			),
		}, nil), nil
	}}
	result := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	).Repositories["owner/one"]
	if runner.calls != maxReviewThreadPages ||
		!strings.Contains(result.Error, "pagination exceeded") {
		t.Fatalf("calls=%d result=%#v", runner.calls, result)
	}
}
