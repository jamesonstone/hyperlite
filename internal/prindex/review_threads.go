package prindex

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/config"
)

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

type rawReviewThreadPullRequest struct {
	ReviewThreads *rawReviewThreadConnection `json:"reviewThreads"`
}

type rawReviewThreadRepository struct {
	PullRequest *rawReviewThreadPullRequest `json:"pullRequest"`
}

type rawReviewThreadResponse struct {
	Data   map[string]json.RawMessage `json:"data"`
	Errors []rawGraphQLError          `json:"errors"`
}

func (c GitHubClient) collectReviewThreadPages(
	ctx context.Context,
	pending []reviewThreadPageRequest,
	results map[string]RepositoryResult,
	collector *rateLimitCollector,
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
		collector.observe(response.Data)
		errorsByAlias, globalErrors := graphQLErrors(response.Errors)
		for alias, request := range aliases {
			key := repositoryKey(request.repository.GitHub)
			if results[key].Error != "" {
				continue
			}
			raw, found, decodeErr := decodeGraphQLData[rawReviewThreadRepository](
				response.Data, alias,
			)
			messages := append([]string{}, globalErrors...)
			messages = append(messages, errorsByAlias[alias]...)
			if decodeErr != nil {
				setResultError(
					results, request.repository.GitHub,
					"decode GitHub review data: "+decodeErr.Error(),
				)
				continue
			}
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
