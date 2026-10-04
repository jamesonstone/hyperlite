package prindex

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

// probeBatchSize sizes the cheap first pass. A probe selects only the open
// pull request count and repository activity, so it stays fast and costs a
// fraction of the detail query even for many repositories.
const probeBatchSize = 10

// probeResult is one repository's first-pass outcome. Final results need no
// detail query: the repository has no open pull requests or GitHub reported a
// repository-scoped error.
type probeResult struct {
	result    RepositoryResult
	final     bool
	openCount int
}

func buildProbeQuery(repositories []config.Repository) (string, map[string]config.Repository) {
	var query strings.Builder
	query.WriteString("query {\n")
	aliases := make(map[string]config.Repository, len(repositories))
	for index, repository := range repositories {
		alias := "repository" + strconv.Itoa(index)
		aliases[alias] = repository
		writeRepositoryOpen(&query, alias, repository)
		query.WriteString("    openPullRequests: pullRequests(states: OPEN) { totalCount }\n")
		writeRepositoryActivitySelections(&query, "    ")
		query.WriteString("  }\n")
	}
	writeRateLimit(&query)
	query.WriteString("}\n")
	return query.String(), aliases
}

// probeBatch returns nothing for repositories whose probe failed outright so
// the detail pass, which splits failing batches, can retry them.
func (c GitHubClient) probeBatch(
	ctx context.Context,
	repositories []config.Repository,
) (map[string]probeResult, rateLimitCollector) {
	var collector rateLimitCollector
	query, aliases := buildProbeQuery(repositories)
	output, err := c.run(ctx, query)
	if err != nil {
		return nil, collector
	}
	var response rawResponse
	if err := json.Unmarshal(output, &response); err != nil {
		return nil, collector
	}
	collector.observe(response.Data)
	errorsByAlias, globalErrors := graphQLErrors(response.Errors)
	results := make(map[string]probeResult, len(aliases))
	for alias, repository := range aliases {
		key := repositoryKey(repository.GitHub)
		raw, found, decodeErr := decodeGraphQLData[rawRepository](response.Data, alias)
		messages := append(append([]string{}, globalErrors...), errorsByAlias[alias]...)
		switch {
		case decodeErr != nil || len(globalErrors) > 0:
			continue
		case !found || raw == nil || len(messages) > 0:
			if len(messages) == 0 {
				messages = append(messages, "GitHub returned no repository data")
			}
			results[key] = probeResult{
				result: RepositoryResult{Error: strings.Join(messages, "; ")}, final: true,
			}
		case raw.OpenPullRequests == nil:
			results[key] = probeResult{}
		case raw.OpenPullRequests.TotalCount > 0:
			results[key] = probeResult{openCount: raw.OpenPullRequests.TotalCount}
		default:
			results[key] = probeResult{final: true, result: RepositoryResult{
				PullRequests: []model.ProjectPullRequest{},
				Activity:     repositoryActivityFromRaw(nil, raw, repository.GitHub),
			}}
		}
	}
	return results, collector
}
