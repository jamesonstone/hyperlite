package prindex

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

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
				"headRefOid":  fmt.Sprintf("head-%d", number),
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
