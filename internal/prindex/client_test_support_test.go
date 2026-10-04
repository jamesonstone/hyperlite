package prindex

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
)

// graphQLRunner serializes fake responses because ListOpen issues batches
// concurrently.
// Probe queries are answered by probe, or by default as one open pull request
// per repository, and are not counted in calls so detail-query sequencing
// stays independent of the probe pass.
type graphQLRunner struct {
	mutex      sync.Mutex
	calls      int
	probeCalls int
	queries    []string
	respond    func(string, int) ([]byte, error)
	probe      func(string) ([]byte, error)
}

func (r *graphQLRunner) Run(
	_ context.Context,
	_ string,
	name string,
	args ...string,
) ([]byte, error) {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	if len(args) == 4 && strings.Contains(args[3], probeSelection) {
		r.probeCalls++
		query := strings.TrimPrefix(args[3], "query=")
		if r.probe != nil {
			return r.probe(query)
		}
		return probeResponse(query, 1), nil
	}
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

const probeSelection = "openPullRequests: pullRequests(states: OPEN"

func probeResponse(query string, openCount int) []byte {
	count := strings.Count(query, ": repository(")
	data := make(map[string]any, count)
	for index := 0; index < count; index++ {
		data[fmt.Sprintf("repository%d", index)] = map[string]any{
			"openPullRequests": map[string]any{"totalCount": openCount},
		}
	}
	return responseJSON(data, nil)
}

// queriedRepository returns the repository name of a single-repository query.
func queriedRepository(query string) string {
	_, rest, found := strings.Cut(query, `name: "`)
	if !found {
		return ""
	}
	name, _, _ := strings.Cut(rest, `"`)
	return name
}
