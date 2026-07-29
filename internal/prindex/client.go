package prindex

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

const (
	githubTimeout  = 20 * time.Second
	queryBatchSize = 25
	queryPageSize  = 100
)

type RepositoryResult struct {
	PullRequests []model.ProjectPullRequest
	Error        string
}

type GitHubClient struct {
	Runner command.Runner
}

type pageRequest struct {
	repository config.Repository
	cursor     string
}

type rawPullRequest struct {
	Number    int       `json:"number"`
	Title     string    `json:"title"`
	URL       string    `json:"url"`
	IsDraft   bool      `json:"isDraft"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type rawRepository struct {
	PullRequests struct {
		Nodes    []rawPullRequest `json:"nodes"`
		PageInfo struct {
			HasNextPage bool   `json:"hasNextPage"`
			EndCursor   string `json:"endCursor"`
		} `json:"pageInfo"`
	} `json:"pullRequests"`
}

type rawGraphQLError struct {
	Message string            `json:"message"`
	Path    []json.RawMessage `json:"path"`
}

type rawResponse struct {
	Data   map[string]*rawRepository `json:"data"`
	Errors []rawGraphQLError         `json:"errors"`
}

func (c GitHubClient) ListOpen(
	ctx context.Context,
	repositories []config.Repository,
) map[string]RepositoryResult {
	unique := uniqueRepositories(repositories)
	results := make(map[string]RepositoryResult, len(unique))
	for start := 0; start < len(unique); start += queryBatchSize {
		end := min(start+queryBatchSize, len(unique))
		c.collectBatch(ctx, unique[start:end], results)
	}
	return results
}

func (c GitHubClient) collectBatch(
	ctx context.Context,
	repositories []config.Repository,
	results map[string]RepositoryResult,
) {
	pending := make([]pageRequest, 0, len(repositories))
	for _, repository := range repositories {
		pending = append(pending, pageRequest{repository: repository})
		results[repositoryKey(repository.GitHub)] = RepositoryResult{
			PullRequests: []model.ProjectPullRequest{},
		}
	}
	for len(pending) > 0 {
		query, aliases := buildQuery(pending)
		output, err := c.run(ctx, query)
		if err != nil {
			for _, request := range pending {
				setResultError(results, request.repository.GitHub, err.Error())
			}
			return
		}
		var response rawResponse
		if err := json.Unmarshal(output, &response); err != nil {
			message := "decode GraphQL response: " + err.Error()
			for _, request := range pending {
				setResultError(results, request.repository.GitHub, message)
			}
			return
		}
		errorsByAlias, globalErrors := graphQLErrors(response.Errors)
		var next []pageRequest
		for alias, request := range aliases {
			raw, found := response.Data[alias]
			messages := append([]string{}, globalErrors...)
			messages = append(messages, errorsByAlias[alias]...)
			if !found || raw == nil {
				if len(messages) == 0 {
					messages = append(messages, "GitHub returned no repository data")
				}
				setResultError(results, request.repository.GitHub, strings.Join(messages, "; "))
				continue
			}
			if len(messages) > 0 {
				setResultError(results, request.repository.GitHub, strings.Join(messages, "; "))
				continue
			}
			key := repositoryKey(request.repository.GitHub)
			result := results[key]
			for _, pullRequest := range raw.PullRequests.Nodes {
				result.PullRequests = append(result.PullRequests, model.ProjectPullRequest{
					ID:     fmt.Sprintf("%s#%d", request.repository.GitHub, pullRequest.Number),
					Number: pullRequest.Number, Title: pullRequest.Title,
					URL: pullRequest.URL, IsDraft: pullRequest.IsDraft,
					UpdatedAt: pullRequest.UpdatedAt.UTC(),
				})
			}
			results[key] = result
			if raw.PullRequests.PageInfo.HasNextPage {
				if raw.PullRequests.PageInfo.EndCursor == "" {
					setResultError(results, request.repository.GitHub, "GitHub pagination cursor is missing")
					continue
				}
				request.cursor = raw.PullRequests.PageInfo.EndCursor
				next = append(next, request)
			}
		}
		pending = next
	}
	for key, result := range results {
		sort.Slice(result.PullRequests, func(i, j int) bool {
			if !result.PullRequests[i].UpdatedAt.Equal(result.PullRequests[j].UpdatedAt) {
				return result.PullRequests[i].UpdatedAt.After(result.PullRequests[j].UpdatedAt)
			}
			return result.PullRequests[i].Number < result.PullRequests[j].Number
		})
		results[key] = result
	}
}

func (c GitHubClient) run(ctx context.Context, query string) ([]byte, error) {
	if c.Runner == nil {
		return nil, errors.New("GitHub command runner is not configured")
	}
	commandContext, cancel := context.WithTimeout(ctx, githubTimeout)
	defer cancel()
	output, err := c.Runner.Run(
		commandContext, "", "gh", "api", "graphql", "-f", "query="+query,
	)
	if err == nil {
		return output, nil
	}
	var commandError *command.Error
	if errors.As(err, &commandError) {
		if detail := strings.TrimSpace(commandError.Stderr); detail != "" {
			return output, errors.New(detail)
		}
		if commandError.Err != nil {
			return output, commandError.Err
		}
	}
	return output, err
}

func uniqueRepositories(repositories []config.Repository) []config.Repository {
	seen := make(map[string]struct{}, len(repositories))
	result := make([]config.Repository, 0, len(repositories))
	for _, repository := range repositories {
		key := repositoryKey(repository.GitHub)
		if key == "" {
			continue
		}
		if _, found := seen[key]; found {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, repository)
	}
	return result
}

func setResultError(results map[string]RepositoryResult, repository, message string) {
	key := repositoryKey(repository)
	result := results[key]
	result.Error = message
	results[key] = result
}

func repositoryKey(repository string) string {
	return strings.ToLower(strings.TrimSpace(repository))
}
