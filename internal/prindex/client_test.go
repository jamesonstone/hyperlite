package prindex

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestGitHubClientBatchesRepositoriesAndPaginatesOnlyWhenNeeded(t *testing.T) {
	runner := &graphQLRunner{respond: func(query string, call int) ([]byte, error) {
		switch call {
		case 1:
			if !strings.Contains(query, `name: "one"`) ||
				!strings.Contains(query, `name: "two"`) ||
				!strings.Contains(query, "headRefOid") ||
				!strings.Contains(query, `nodes { isResolved isOutdated }`) {
				t.Fatalf("first query = %s", query)
			}
			return responseJSON(map[string]any{
				"repository0": repositoryPage(1, true, "cursor-one"),
				"repository1": repositoryPage(2, false, ""),
			}, nil), nil
		case 2:
			if !strings.Contains(query, `after: "cursor-one"`) ||
				strings.Contains(query, `name: "two"`) {
				t.Fatalf("pagination query = %s", query)
			}
			return responseJSON(map[string]any{
				"repository0": repositoryPage(3, false, ""),
			}, nil), nil
		default:
			t.Fatalf("unexpected call %d", call)
			return nil, nil
		}
	}}
	client := GitHubClient{Runner: runner}
	results := client.ListOpen(context.Background(), []config.Repository{
		{GitHub: "owner/one"},
		{GitHub: "owner/two"},
	}).Repositories
	if runner.calls != 2 {
		t.Fatalf("calls = %d", runner.calls)
	}
	if got := results["owner/one"]; got.Error != "" ||
		len(got.PullRequests) != 2 ||
		got.PullRequests[0].Number != 3 ||
		got.PullRequests[0].HeadRefName != "GH-3" ||
		got.PullRequests[0].HeadRefOID != "head-3" ||
		got.PullRequests[1].Number != 1 {
		t.Fatalf("owner/one = %#v", got)
	}
	if got := results["owner/two"]; got.Error != "" ||
		len(got.PullRequests) != 1 || got.PullRequests[0].Number != 2 {
		t.Fatalf("owner/two = %#v", got)
	}
}

func TestGitHubClientCountsOnlyActionableReviewThreads(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		return responseJSON(map[string]any{
			"repository0": repositoryPageWithReviewThreads(
				1, false, "",
				[]map[string]any{
					{"isResolved": false, "isOutdated": false},
					{"isResolved": true, "isOutdated": false},
					{"isResolved": false, "isOutdated": true},
					{"isResolved": true, "isOutdated": true},
				},
				false, "",
			),
		}, nil), nil
	}}
	result := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	).Repositories["owner/one"]
	if result.Error != "" || len(result.PullRequests) != 1 ||
		result.PullRequests[0].UnresolvedReviewThreads == nil ||
		*result.PullRequests[0].UnresolvedReviewThreads != 1 {
		t.Fatalf("result = %#v", result)
	}
}

func TestGitHubClientRejectsMissingHeadCommit(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		page := repositoryPage(1, false, "")
		pullRequests := page["pullRequests"].(map[string]any)
		nodes := pullRequests["nodes"].([]map[string]any)
		delete(nodes[0], "headRefOid")
		return responseJSON(map[string]any{"repository0": page}, nil), nil
	}}
	result := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	).Repositories["owner/one"]
	if result.Error != "GitHub returned no pull request head commit" ||
		len(result.PullRequests) != 0 {
		t.Fatalf("result = %#v", result)
	}
}

func TestGitHubClientPaginatesReviewThreadsOnlyWhenNeeded(t *testing.T) {
	runner := &graphQLRunner{respond: func(query string, call int) ([]byte, error) {
		switch call {
		case 1:
			return responseJSON(map[string]any{
				"repository0": repositoryPageWithReviewThreads(
					1, false, "",
					[]map[string]any{{"isResolved": false, "isOutdated": false}},
					true, "review-cursor-one",
				),
			}, nil), nil
		case 2:
			if !strings.Contains(query, `pullRequest(number: 1)`) ||
				!strings.Contains(query, `after: "review-cursor-one"`) ||
				strings.Contains(query, "pullRequests(states: OPEN") ||
				!strings.Contains(
					query,
					"rateLimit { limit used remaining resetAt cost nodeCount }",
				) {
				t.Fatalf("review pagination query = %s", query)
			}
			return responseJSON(map[string]any{
				"repository0": reviewThreadRepositoryPage(
					[]map[string]any{
						{"isResolved": false, "isOutdated": false},
						{"isResolved": true, "isOutdated": false},
					},
					false, "",
				),
			}, nil), nil
		default:
			t.Fatalf("unexpected call %d", call)
			return nil, nil
		}
	}}
	result := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	).Repositories["owner/one"]
	if runner.calls != 2 || result.Error != "" ||
		result.PullRequests[0].UnresolvedReviewThreads == nil ||
		*result.PullRequests[0].UnresolvedReviewThreads != 2 {
		t.Fatalf("calls=%d result=%#v", runner.calls, result)
	}
}

func TestGitHubClientRejectsMissingReviewThreadData(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		page := repositoryPage(1, false, "")
		pullRequests := page["pullRequests"].(map[string]any)
		nodes := pullRequests["nodes"].([]map[string]any)
		delete(nodes[0], "reviewThreads")
		return responseJSON(map[string]any{"repository0": page}, nil), nil
	}}
	result := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	).Repositories["owner/one"]
	if !strings.Contains(result.Error, "no review thread data") {
		t.Fatalf("result = %#v", result)
	}
}

func TestGitHubClientUsesBoundedBatches(t *testing.T) {
	runner := &graphQLRunner{respond: func(query string, _ int) ([]byte, error) {
		count := strings.Count(query, ": repository(")
		data := make(map[string]any, count)
		for index := 0; index < count; index++ {
			data[fmt.Sprintf("repository%d", index)] = repositoryPage(index+1, false, "")
		}
		return responseJSON(data, nil), nil
	}}
	var repositories []config.Repository
	for index := 0; index < queryBatchSize+1; index++ {
		repositories = append(repositories, config.Repository{
			GitHub: fmt.Sprintf("owner/repository-%02d", index),
		})
	}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), repositories,
	).Repositories
	if runner.calls != 2 || len(results) != len(repositories) {
		t.Fatalf("calls=%d results=%d", runner.calls, len(results))
	}
}

func TestGitHubClientKeepsPartialGraphQLFailureRepositoryScoped(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		return responseJSON(
			map[string]any{
				"repository0": repositoryPage(1, false, ""),
				"repository1": nil,
			},
			[]map[string]any{{
				"message": "Repository not found",
				"path":    []any{"repository1"},
			}},
		), nil
	}}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(),
		[]config.Repository{{GitHub: "owner/one"}, {GitHub: "owner/two"}},
	).Repositories
	if results["owner/one"].Error != "" || len(results["owner/one"].PullRequests) != 1 {
		t.Fatalf("owner/one = %#v", results["owner/one"])
	}
	if !strings.Contains(results["owner/two"].Error, "Repository not found") {
		t.Fatalf("owner/two = %#v", results["owner/two"])
	}
}

func TestGitHubClientCompletesReviewPaginationForUnaffectedRepository(t *testing.T) {
	runner := &graphQLRunner{respond: func(query string, call int) ([]byte, error) {
		switch call {
		case 1:
			return responseJSON(map[string]any{
				"repository0": repositoryPage(1, true, "pull-request-cursor"),
				"repository1": repositoryPageWithReviewThreads(
					2, false, "",
					[]map[string]any{{"isResolved": false, "isOutdated": false}},
					true, "review-thread-cursor",
				),
			}, nil), nil
		case 2:
			if !strings.Contains(query, `after: "pull-request-cursor"`) {
				t.Fatalf("pull request pagination query = %s", query)
			}
			return nil, errors.New("pull request pagination failed")
		case 3:
			if !strings.Contains(query, `after: "review-thread-cursor"`) {
				t.Fatalf("review thread pagination query = %s", query)
			}
			return responseJSON(map[string]any{
				"repository0": reviewThreadRepositoryPage(
					[]map[string]any{{"isResolved": false, "isOutdated": false}},
					false, "",
				),
			}, nil), nil
		default:
			t.Fatalf("unexpected call %d", call)
			return nil, nil
		}
	}}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(),
		[]config.Repository{{GitHub: "owner/one"}, {GitHub: "owner/two"}},
	).Repositories
	if !strings.Contains(results["owner/one"].Error, "pagination failed") {
		t.Fatalf("owner/one = %#v", results["owner/one"])
	}
	ownerTwo := results["owner/two"]
	if runner.calls != 3 || ownerTwo.Error != "" ||
		ownerTwo.PullRequests[0].UnresolvedReviewThreads == nil ||
		*ownerTwo.PullRequests[0].UnresolvedReviewThreads != 2 {
		t.Fatalf("calls=%d owner/two=%#v", runner.calls, ownerTwo)
	}
}

func TestGitHubClientDoesNotExposeGraphQLQueryOnCommandFailure(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		return nil, &command.Error{
			Name: "gh", Args: []string{"api", "graphql", "query=large query"},
			Stderr: "rate limit exceeded", Err: errors.New("exit status 1"),
		}
	}}
	results := (GitHubClient{Runner: runner}).ListOpen(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	).Repositories
	if results["owner/one"].Error != "rate limit exceeded" ||
		strings.Contains(results["owner/one"].Error, "pullRequests") {
		t.Fatalf("result = %#v", results["owner/one"])
	}
}
