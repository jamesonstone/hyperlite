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
	githubTimeout        = 20 * time.Second
	queryBatchSize       = 25
	queryPageSize        = 100
	reviewThreadPageSize = 100
	maxRepositoryPages   = 20
	maxReviewThreadPages = 20
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
	page       int
}

type reviewThreadPageRequest struct {
	repository        config.Repository
	pullRequestNumber int
	cursor            string
	page              int
}

type rawReviewThread struct {
	IsResolved bool `json:"isResolved"`
	IsOutdated bool `json:"isOutdated"`
}

type rawReviewThreadConnection struct {
	Nodes    []rawReviewThread `json:"nodes"`
	PageInfo struct {
		HasNextPage bool   `json:"hasNextPage"`
		EndCursor   string `json:"endCursor"`
	} `json:"pageInfo"`
}

type rawPullRequest struct {
	Number        int                        `json:"number"`
	Title         string                     `json:"title"`
	URL           string                     `json:"url"`
	HeadRefName   string                     `json:"headRefName"`
	IsDraft       bool                       `json:"isDraft"`
	UpdatedAt     time.Time                  `json:"updatedAt"`
	ReviewThreads *rawReviewThreadConnection `json:"reviewThreads"`
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

type rawReviewThreadPullRequest struct {
	ReviewThreads *rawReviewThreadConnection `json:"reviewThreads"`
}

type rawReviewThreadRepository struct {
	PullRequest *rawReviewThreadPullRequest `json:"pullRequest"`
}

type rawReviewThreadResponse struct {
	Data   map[string]*rawReviewThreadRepository `json:"data"`
	Errors []rawGraphQLError                     `json:"errors"`
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
	var reviewThreadPages []reviewThreadPageRequest
	for _, repository := range repositories {
		pending = append(pending, pageRequest{repository: repository, page: 1})
		results[repositoryKey(repository.GitHub)] = RepositoryResult{
			PullRequests: []model.ProjectPullRequest{},
		}
	}
	seenCursors := make(map[string]map[string]struct{}, len(repositories))
	for len(pending) > 0 {
		query, aliases := buildQuery(pending)
		output, err := c.run(ctx, query)
		if err != nil {
			for _, request := range pending {
				setResultError(results, request.repository.GitHub, err.Error())
			}
			break
		}
		var response rawResponse
		if err := json.Unmarshal(output, &response); err != nil {
			message := "decode GraphQL response: " + err.Error()
			for _, request := range pending {
				setResultError(results, request.repository.GitHub, message)
			}
			break
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
				if pullRequest.ReviewThreads == nil {
					result.Error = "GitHub returned no review thread data"
					continue
				}
				unresolvedReviewThreads := actionableReviewThreadCount(
					pullRequest.ReviewThreads.Nodes,
				)
				result.PullRequests = append(result.PullRequests, model.ProjectPullRequest{
					ID:     fmt.Sprintf("%s#%d", request.repository.GitHub, pullRequest.Number),
					Number: pullRequest.Number, Title: pullRequest.Title,
					URL: pullRequest.URL, HeadRefName: pullRequest.HeadRefName,
					IsDraft:                 pullRequest.IsDraft,
					UnresolvedReviewThreads: &unresolvedReviewThreads,
					UpdatedAt:               pullRequest.UpdatedAt.UTC(),
				})
				if pullRequest.ReviewThreads.PageInfo.HasNextPage {
					cursor := pullRequest.ReviewThreads.PageInfo.EndCursor
					if cursor == "" {
						result.Error = "GitHub review-thread pagination cursor is missing"
						continue
					}
					if maxReviewThreadPages <= 1 {
						result.Error = fmt.Sprintf(
							"GitHub review-thread pagination exceeded %d pages",
							maxReviewThreadPages,
						)
						continue
					}
					reviewThreadPages = append(
						reviewThreadPages,
						reviewThreadPageRequest{
							repository: request.repository, pullRequestNumber: pullRequest.Number,
							cursor: cursor, page: 2,
						},
					)
				}
			}
			results[key] = result
			if result.Error != "" {
				continue
			}
			if raw.PullRequests.PageInfo.HasNextPage {
				cursor := raw.PullRequests.PageInfo.EndCursor
				if cursor == "" {
					setResultError(results, request.repository.GitHub, "GitHub pagination cursor is missing")
					continue
				}
				key := repositoryKey(request.repository.GitHub)
				if seenCursors[key] == nil {
					seenCursors[key] = make(map[string]struct{})
				}
				if _, repeated := seenCursors[key][cursor]; repeated {
					setResultError(results, request.repository.GitHub, "GitHub pagination cursor repeated")
					continue
				}
				if request.page >= maxRepositoryPages {
					setResultError(
						results,
						request.repository.GitHub,
						fmt.Sprintf("GitHub pagination exceeded %d pages", maxRepositoryPages),
					)
					continue
				}
				seenCursors[key][cursor] = struct{}{}
				request.cursor = cursor
				request.page++
				next = append(next, request)
			}
		}
		pending = next
	}
	c.collectReviewThreadPages(ctx, reviewThreadPages, results)
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

func (c GitHubClient) collectReviewThreadPages(
	ctx context.Context,
	pending []reviewThreadPageRequest,
	results map[string]RepositoryResult,
) {
	seenCursors := make(map[string]map[string]struct{})
	for _, request := range pending {
		key := reviewThreadRequestKey(request)
		if seenCursors[key] == nil {
			seenCursors[key] = make(map[string]struct{})
		}
		seenCursors[key][request.cursor] = struct{}{}
	}
	for len(pending) > 0 {
		pending = reviewThreadRequestsWithoutErrors(pending, results)
		if len(pending) == 0 {
			return
		}
		end := min(queryBatchSize, len(pending))
		batch := pending[:end]
		pending = pending[end:]
		query, aliases := buildReviewThreadQuery(batch)
		output, err := c.run(ctx, query)
		if err != nil {
			for _, request := range batch {
				setResultError(results, request.repository.GitHub, err.Error())
			}
			continue
		}
		var response rawReviewThreadResponse
		if err := json.Unmarshal(output, &response); err != nil {
			message := "decode GraphQL response: " + err.Error()
			for _, request := range batch {
				setResultError(results, request.repository.GitHub, message)
			}
			continue
		}
		errorsByAlias, globalErrors := graphQLErrors(response.Errors)
		for alias, request := range aliases {
			key := repositoryKey(request.repository.GitHub)
			if results[key].Error != "" {
				continue
			}
			raw, found := response.Data[alias]
			messages := append([]string{}, globalErrors...)
			messages = append(messages, errorsByAlias[alias]...)
			if !found || raw == nil || raw.PullRequest == nil {
				if len(messages) == 0 {
					messages = append(messages, "GitHub returned no pull request review data")
				}
				setResultError(results, request.repository.GitHub, strings.Join(messages, "; "))
				continue
			}
			if len(messages) > 0 {
				setResultError(results, request.repository.GitHub, strings.Join(messages, "; "))
				continue
			}
			if raw.PullRequest.ReviewThreads == nil {
				setResultError(results, request.repository.GitHub, "GitHub returned no review thread data")
				continue
			}
			result := results[key]
			count := actionableReviewThreadCount(raw.PullRequest.ReviewThreads.Nodes)
			if !addReviewThreadCount(&result, request.pullRequestNumber, count) {
				setResultError(
					results,
					request.repository.GitHub,
					"GitHub returned review threads for an unknown pull request",
				)
				continue
			}
			results[key] = result
			if !raw.PullRequest.ReviewThreads.PageInfo.HasNextPage {
				continue
			}
			cursor := raw.PullRequest.ReviewThreads.PageInfo.EndCursor
			if cursor == "" {
				setResultError(
					results,
					request.repository.GitHub,
					"GitHub review-thread pagination cursor is missing",
				)
				continue
			}
			requestKey := reviewThreadRequestKey(request)
			if _, repeated := seenCursors[requestKey][cursor]; repeated {
				setResultError(
					results,
					request.repository.GitHub,
					"GitHub review-thread pagination cursor repeated",
				)
				continue
			}
			if request.page >= maxReviewThreadPages {
				setResultError(
					results,
					request.repository.GitHub,
					fmt.Sprintf(
						"GitHub review-thread pagination exceeded %d pages",
						maxReviewThreadPages,
					),
				)
				continue
			}
			seenCursors[requestKey][cursor] = struct{}{}
			request.cursor = cursor
			request.page++
			pending = append(pending, request)
		}
	}
}

func actionableReviewThreadCount(threads []rawReviewThread) int {
	count := 0
	for _, thread := range threads {
		if !thread.IsResolved && !thread.IsOutdated {
			count++
		}
	}
	return count
}

func addReviewThreadCount(result *RepositoryResult, number, count int) bool {
	for index := range result.PullRequests {
		pullRequest := &result.PullRequests[index]
		if pullRequest.Number != number || pullRequest.UnresolvedReviewThreads == nil {
			continue
		}
		total := *pullRequest.UnresolvedReviewThreads + count
		pullRequest.UnresolvedReviewThreads = &total
		return true
	}
	return false
}

func reviewThreadRequestsWithoutErrors(
	requests []reviewThreadPageRequest,
	results map[string]RepositoryResult,
) []reviewThreadPageRequest {
	filtered := requests[:0]
	for _, request := range requests {
		if results[repositoryKey(request.repository.GitHub)].Error == "" {
			filtered = append(filtered, request)
		}
	}
	return filtered
}

func reviewThreadRequestKey(request reviewThreadPageRequest) string {
	return fmt.Sprintf(
		"%s#%d",
		repositoryKey(request.repository.GitHub),
		request.pullRequestNumber,
	)
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
