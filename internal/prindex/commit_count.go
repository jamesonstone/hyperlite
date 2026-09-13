package prindex

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/config"
)

const (
	commitCountSourceGitHub = "github"
	commitCountSourceLocal  = "local"
)

type CommitCountEntry struct {
	Count int
	Error string
}

type CommitCountResult struct {
	Repositories map[string]CommitCountEntry
	RateLimit    *GitHubRateLimit
}

type rawCommitCountRepository struct {
	DefaultBranchRef *struct {
		Target *struct {
			History *struct {
				TotalCount int `json:"totalCount"`
			} `json:"history"`
		} `json:"target"`
	} `json:"defaultBranchRef"`
}

func buildCommitCountQuery(repositories []config.Repository) (string, map[string]config.Repository) {
	var query strings.Builder
	query.WriteString("query {\n")
	aliases := make(map[string]config.Repository, len(repositories))
	for index, repository := range repositories {
		owner, name, _ := strings.Cut(repository.GitHub, "/")
		alias := "repository" + strconv.Itoa(index)
		aliases[alias] = repository
		query.WriteString("  ")
		query.WriteString(alias)
		query.WriteString(": repository(owner: ")
		query.WriteString(strconv.Quote(owner))
		query.WriteString(", name: ")
		query.WriteString(strconv.Quote(name))
		query.WriteString(") {\n")
		query.WriteString("    defaultBranchRef { target { ... on Commit { history(first: 1) { totalCount } } } }\n")
		query.WriteString("  }\n")
	}
	writeRateLimit(&query)
	query.WriteString("}\n")
	return query.String(), aliases
}

// FetchCommitCounts reads default-branch history totals. It never lists
// pull requests or workflow files.
func (c GitHubClient) FetchCommitCounts(
	ctx context.Context,
	repositories []config.Repository,
) CommitCountResult {
	unique := uniqueRepositories(repositories)
	result := CommitCountResult{Repositories: make(map[string]CommitCountEntry, len(unique))}
	collector := rateLimitCollector{}
	for start := 0; start < len(unique); start += queryBatchSize {
		batch := unique[start:min(start+queryBatchSize, len(unique))]
		query, aliases := buildCommitCountQuery(batch)
		output, err := c.run(ctx, query)
		if err != nil {
			setCommitCountError(result.Repositories, batch, err.Error())
			continue
		}
		var response rawResponse
		if err := json.Unmarshal(output, &response); err != nil {
			setCommitCountError(result.Repositories, batch, "decode GraphQL response: "+err.Error())
			continue
		}
		collector.observe(response.Data)
		errorsByAlias, globalErrors := graphQLErrors(response.Errors)
		for alias, repository := range aliases {
			key := repositoryKey(repository.GitHub)
			messages := append(append([]string{}, globalErrors...), errorsByAlias[alias]...)
			raw, found, decodeErr := decodeGraphQLData[rawCommitCountRepository](response.Data, alias)
			switch {
			case decodeErr != nil:
				result.Repositories[key] = CommitCountEntry{Error: "decode GitHub commit count: " + decodeErr.Error()}
			case !found || raw == nil:
				if len(messages) == 0 {
					messages = append(messages, "GitHub returned no repository data")
				}
				result.Repositories[key] = CommitCountEntry{Error: strings.Join(messages, "; ")}
			case len(messages) > 0:
				result.Repositories[key] = CommitCountEntry{Error: strings.Join(messages, "; ")}
			default:
				result.Repositories[key] = commitCountEntry(raw)
			}
		}
	}
	result.RateLimit = collector.latest
	return result
}

func commitCountEntry(raw *rawCommitCountRepository) CommitCountEntry {
	if raw == nil || raw.DefaultBranchRef == nil || raw.DefaultBranchRef.Target == nil ||
		raw.DefaultBranchRef.Target.History == nil {
		return CommitCountEntry{Error: "GitHub returned no default-branch history"}
	}
	return CommitCountEntry{Count: raw.DefaultBranchRef.Target.History.TotalCount}
}

func setCommitCountError(
	results map[string]CommitCountEntry,
	repositories []config.Repository,
	message string,
) {
	for _, repository := range repositories {
		results[repositoryKey(repository.GitHub)] = CommitCountEntry{Error: message}
	}
}
