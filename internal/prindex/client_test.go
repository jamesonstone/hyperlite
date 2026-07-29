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
				!strings.Contains(query, `name: "two"`) {
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
	})
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
	results := (GitHubClient{Runner: runner}).ListOpen(context.Background(), repositories)
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
	)
	if results["owner/one"].Error != "" || len(results["owner/one"].PullRequests) != 1 {
		t.Fatalf("owner/one = %#v", results["owner/one"])
	}
	if !strings.Contains(results["owner/two"].Error, "Repository not found") {
		t.Fatalf("owner/two = %#v", results["owner/two"])
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
	)
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
	)
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
	)
	if runner.calls != maxRepositoryPages ||
		!strings.Contains(results["owner/one"].Error, "pagination exceeded") {
		t.Fatalf("calls=%d result=%#v", runner.calls, results["owner/one"])
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
	return map[string]any{
		"pullRequests": map[string]any{
			"nodes": []map[string]any{{
				"number":      number,
				"title":       fmt.Sprintf("Pull request %d", number),
				"url":         fmt.Sprintf("https://github.com/owner/repo/pull/%d", number),
				"headRefName": fmt.Sprintf("GH-%d", number),
				"isDraft":     number%2 == 0,
				"updatedAt":   fmt.Sprintf("2026-07-29T12:%02d:00Z", number),
			}},
			"pageInfo": map[string]any{
				"hasNextPage": hasNext,
				"endCursor":   cursor,
			},
		},
	}
}

func responseJSON(data map[string]any, graphQLErrors []map[string]any) []byte {
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
