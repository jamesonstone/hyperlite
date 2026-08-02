package prindex

import (
	"context"
	"encoding/json"
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

type graphQLRunner struct {
	calls   int
	queries []string
	respond func(string, int) ([]byte, error)
}

func (r *graphQLRunner) Run(
	_ context.Context,
	_ string,
	name string,
	args ...string,
) ([]byte, error) {
	r.calls++
	if name != "gh" || len(args) != 4 ||
		args[0] != "api" || args[1] != "graphql" ||
		args[2] != "-f" || !strings.HasPrefix(args[3], "query=") {
		return nil, fmt.Errorf("unexpected command: %s %v", name, args)
	}
	query := strings.TrimPrefix(args[3], "query=")
	r.queries = append(r.queries, query)
	return r.respond(query, r.calls)
}

func repositoryPage(number int, hasNext bool, cursor string) map[string]any {
	return repositoryPageWithReviewThreads(
		number, hasNext, cursor, nil, false, "",
	)
}

func repositoryPageWithReviewThreads(
	number int,
	pullRequestsHaveNext bool,
	pullRequestsCursor string,
	reviewThreads []map[string]any,
	reviewThreadsHaveNext bool,
	reviewThreadsCursor string,
) map[string]any {
	return map[string]any{
		"pullRequests": map[string]any{
			"nodes": []map[string]any{{
				"number":      number,
				"title":       fmt.Sprintf("Pull request %d", number),
				"url":         fmt.Sprintf("https://github.com/owner/repo/pull/%d", number),
				"headRefName": fmt.Sprintf("GH-%d", number),
				"isDraft":     number%2 == 0,
				"updatedAt":   fmt.Sprintf("2026-07-29T12:%02d:00Z", number),
				"reviewThreads": reviewThreadPage(
					reviewThreads, reviewThreadsHaveNext, reviewThreadsCursor,
				),
			}},
			"pageInfo": map[string]any{
				"hasNextPage": pullRequestsHaveNext,
				"endCursor":   pullRequestsCursor,
			},
		},
	}
}

func reviewThreadRepositoryPage(
	threads []map[string]any,
	hasNext bool,
	cursor string,
) map[string]any {
	return map[string]any{
		"pullRequest": map[string]any{
			"reviewThreads": reviewThreadPage(threads, hasNext, cursor),
		},
	}
}

func reviewThreadPage(
	threads []map[string]any,
	hasNext bool,
	cursor string,
) map[string]any {
	if threads == nil {
		threads = []map[string]any{}
	}
	return map[string]any{
		"nodes": threads,
		"pageInfo": map[string]any{
			"hasNextPage": hasNext,
			"endCursor":   cursor,
		},
	}
}

func responseJSON(data map[string]any, graphQLErrors []map[string]any) []byte {
	return responseJSONWithRateLimit(data, graphQLErrors, nil)
}

func responseJSONWithRateLimit(
	data map[string]any,
	graphQLErrors []map[string]any,
	rateLimit map[string]any,
) []byte {
	if rateLimit != nil {
		data["rateLimit"] = rateLimit
	}
	value := map[string]any{"data": data}
	if len(graphQLErrors) > 0 {
		value["errors"] = graphQLErrors
	}
	output, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return output
}

func githubRateLimit(used, cost, nodeCount int) map[string]any {
	return map[string]any{
		"limit": 5000, "used": used, "remaining": 5000 - used,
		"resetAt": "2026-08-02T12:00:00Z", "cost": cost, "nodeCount": nodeCount,
	}
}
