package prindex

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestGitHubClientSkipsDetailQueryForRepositoriesWithoutOpenPullRequests(t *testing.T) {
	runner := &graphQLRunner{
		probe: func(query string) ([]byte, error) {
			if !strings.Contains(query, "defaultBranchRef") || strings.Contains(query, "headRefOid") {
				t.Errorf("probe query = %s", query)
			}
			return probeResponse(query, 0), nil
		},
		respond: func(query string, _ int) ([]byte, error) {
			t.Errorf("unexpected detail query = %s", query)
			return nil, errors.New("unexpected")
		},
	}
	repositories := batchRepositories(probeBatchSize + 3)
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), repositories,
	).Repositories
	if runner.probeCalls != 2 || runner.calls != 0 || len(results) != len(repositories) {
		t.Fatalf("probeCalls=%d calls=%d results=%d", runner.probeCalls, runner.calls, len(results))
	}
	for key, result := range results {
		if result.Error != "" || result.PullRequests == nil || len(result.PullRequests) != 0 ||
			result.Activity == nil {
			t.Fatalf("%s = %#v", key, result)
		}
	}
}

func TestGitHubClientFallsBackToDetailQueryWhenProbeFails(t *testing.T) {
	runner := &graphQLRunner{
		probe: func(string) ([]byte, error) { return nil, errors.New("gh: HTTP 502") },
		respond: func(query string, _ int) ([]byte, error) {
			return echoRepositoryPages(query), nil
		},
	}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), batchRepositories(3),
	).Repositories
	if runner.calls != 3 || len(results) != 3 {
		t.Fatalf("calls=%d results=%d", runner.calls, len(results))
	}
	for key, result := range results {
		if result.Error != "" || len(result.PullRequests) != 1 {
			t.Fatalf("%s = %#v", key, result)
		}
	}
}

func TestGitHubClientKeepsProbeRepositoryErrorsFinal(t *testing.T) {
	runner := &graphQLRunner{
		probe: func(string) ([]byte, error) {
			return responseJSON(
				map[string]any{
					"repository0": map[string]any{"openPullRequests": map[string]any{"totalCount": 0}},
					"repository1": nil,
				},
				[]map[string]any{{
					"message": "Could not resolve to a Repository",
					"path":    []string{"repository1"},
				}},
			), nil
		},
		respond: func(query string, _ int) ([]byte, error) {
			t.Errorf("unexpected detail query = %s", query)
			return nil, errors.New("unexpected")
		},
	}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}, {GitHub: "owner/gone"}},
	).Repositories
	if got := results["owner/one"]; got.Error != "" {
		t.Fatalf("owner/one = %#v", got)
	}
	if got := results["owner/gone"]; got.Error != "Could not resolve to a Repository" {
		t.Fatalf("owner/gone = %#v", got)
	}
}
