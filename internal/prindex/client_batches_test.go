package prindex

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
)

func batchRepositories(count int) []config.Repository {
	repositories := make([]config.Repository, 0, count)
	for index := 0; index < count; index++ {
		repositories = append(repositories, config.Repository{
			GitHub: fmt.Sprintf("owner/repository-%02d", index),
		})
	}
	return repositories
}

func echoRepositoryPages(query string) []byte {
	count := strings.Count(query, ": repository(")
	data := make(map[string]any, count)
	for index := 0; index < count; index++ {
		data[fmt.Sprintf("repository%d", index)] = repositoryPage(index+1, false, "")
	}
	return responseJSON(data, nil)
}

func TestGitHubClientQueriesDetailsOneRepositoryAtATime(t *testing.T) {
	runner := &graphQLRunner{
		probe: func(query string) ([]byte, error) { return probeResponse(query, 3), nil },
		respond: func(query string, _ int) ([]byte, error) {
			if count := strings.Count(query, ": repository("); count != 1 {
				t.Errorf("detail query selected %d repositories", count)
			}
			if !strings.Contains(query, "pullRequests(states: OPEN, first: 3,") {
				t.Errorf("detail page was not sized from the probe: %s", query)
			}
			return echoRepositoryPages(query), nil
		},
	}
	repositories := batchRepositories(23)
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), repositories,
	).Repositories
	wantProbes := (len(repositories) + probeBatchSize - 1) / probeBatchSize
	if runner.calls != len(repositories) || runner.probeCalls != wantProbes ||
		len(results) != len(repositories) {
		t.Fatalf("calls=%d probes=%d results=%d", runner.calls, runner.probeCalls, len(results))
	}
	for key, result := range results {
		if result.Error != "" || len(result.PullRequests) != 1 {
			t.Fatalf("%s = %#v", key, result)
		}
	}
}

func TestGitHubClientIsolatesFailingRepository(t *testing.T) {
	runner := &graphQLRunner{respond: func(query string, _ int) ([]byte, error) {
		if strings.Contains(query, `name: "repository-01"`) {
			return nil, errors.New("gh: HTTP 502")
		}
		return echoRepositoryPages(query), nil
	}}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), batchRepositories(2),
	).Repositories
	if got := results["owner/repository-00"]; got.Error != "" || len(got.PullRequests) != 1 {
		t.Fatalf("healthy repository = %#v", got)
	}
	if got := results["owner/repository-01"]; got.Error != "gh: HTTP 502" {
		t.Fatalf("failing repository = %#v", got)
	}
}

func TestGitHubClientUsesDataWhenGHExitsOnPartialGraphQLErrors(t *testing.T) {
	runner := &graphQLRunner{
		probe: func(string) ([]byte, error) {
			return responseJSON(
				map[string]any{
					"repository0": map[string]any{"openPullRequests": map[string]any{"totalCount": 0}},
					"repository1": nil,
				},
				[]map[string]any{{"message": "Could not resolve", "path": []string{"repository1"}}},
			), errors.New("exit status 1")
		},
		respond: func(query string, _ int) ([]byte, error) {
			t.Errorf("unexpected detail query = %s", query)
			return nil, errors.New("unexpected")
		},
	}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), batchRepositories(2),
	).Repositories
	if got := results["owner/repository-00"]; got.Error != "" || got.Activity == nil {
		t.Fatalf("healthy repository = %#v", got)
	}
	if got := results["owner/repository-01"]; got.Error != "Could not resolve" {
		t.Fatalf("missing repository = %#v", got)
	}
}

func TestRateLimitCollectorMergeKeepsMostConsumedObservation(t *testing.T) {
	var collector rateLimitCollector
	collector.merge(rateLimitCollector{latest: &GitHubRateLimit{Remaining: 90}})
	collector.merge(rateLimitCollector{latest: &GitHubRateLimit{Remaining: 80}})
	collector.merge(rateLimitCollector{latest: &GitHubRateLimit{Remaining: 85}})
	collector.merge(rateLimitCollector{})
	if collector.latest == nil || collector.latest.Remaining != 80 {
		t.Fatalf("latest = %#v", collector.latest)
	}
}
