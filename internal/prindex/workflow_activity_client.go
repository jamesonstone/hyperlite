package prindex

import (
	"context"
	"encoding/json"
	"sort"
	"strconv"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

// RepositoryActivityResult is one repository's refreshed Actions state from
// an activity poll. Runs for pull requests that were not polled are absent
// rather than empty so the service can keep their cached state.
type RepositoryActivityResult struct {
	TipOID              string
	TipRuns             []model.WorkflowRun
	Deployments         []model.Deployment
	PullRequestRuns     map[int][]model.WorkflowRun
	DroppedPullRequests map[int]struct{}
	Error               string
}

type ActivityResult struct {
	Repositories map[string]RepositoryActivityResult
	RateLimit    *GitHubRateLimit
}

type rawActivityPullRequest struct {
	Number      int                      `json:"number"`
	State       string                   `json:"state"`
	HeadRefName string                   `json:"headRefName"`
	HeadRefOID  string                   `json:"headRefOid"`
	HeadCommits *rawHeadCommitConnection `json:"headCommits"`
}

// PollActivity refreshes tip runs, deployments, and active pull-request head
// runs in bounded batches. It never lists pull requests or reads workflow
// files.
func (c GitHubClient) PollActivity(
	ctx context.Context,
	requests []ActivityRequest,
) ActivityResult {
	result := ActivityResult{Repositories: make(map[string]RepositoryActivityResult, len(requests))}
	collector := rateLimitCollector{}
	for start := 0; start < len(requests); start += queryBatchSize {
		batch := requests[start:min(start+queryBatchSize, len(requests))]
		query, aliases := buildActivityPollQuery(batch)
		output, err := c.run(ctx, query)
		if err != nil {
			setActivityError(result.Repositories, batch, err.Error())
			continue
		}
		var response rawResponse
		if err := json.Unmarshal(output, &response); err != nil {
			setActivityError(result.Repositories, batch, "decode GraphQL response: "+err.Error())
			continue
		}
		collector.observe(response.Data)
		errorsByAlias, globalErrors := graphQLErrors(response.Errors)
		for alias, request := range aliases {
			key := repositoryKey(request.Repository.GitHub)
			messages := append(append([]string{}, globalErrors...), errorsByAlias[alias]...)
			fields, found, decodeErr := decodeGraphQLData[map[string]json.RawMessage](response.Data, alias)
			switch {
			case decodeErr != nil:
				result.Repositories[key] = RepositoryActivityResult{Error: "decode GitHub activity data: " + decodeErr.Error()}
			case !found || fields == nil:
				if len(messages) == 0 {
					messages = append(messages, "GitHub returned no repository data")
				}
				result.Repositories[key] = RepositoryActivityResult{Error: strings.Join(messages, "; ")}
			case len(messages) > 0:
				result.Repositories[key] = RepositoryActivityResult{Error: strings.Join(messages, "; ")}
			default:
				result.Repositories[key] = activityResultFromFields(*fields)
			}
		}
	}
	result.RateLimit = collector.latest
	return result
}

// collectPendingHeadRuns fetches head runs for pending pull requests found in
// a batch. A failure records a workflow message instead of failing the
// repository's pull-request rows. Only the first maxActivityPullRequests
// pending heads per repository are queried; later ones show no run state
// until they become the most recently updated pending heads.
func (c GitHubClient) collectPendingHeadRuns(
	ctx context.Context,
	results map[string]RepositoryResult,
	collector *rateLimitCollector,
) {
	var requests []ActivityRequest
	for _, key := range sortedKeys(results) {
		result := results[key]
		if result.Error != "" || result.Activity == nil || len(result.Activity.PendingHeads) == 0 {
			continue
		}
		requests = append(requests, ActivityRequest{
			Repository:         config.Repository{GitHub: result.Activity.Repository},
			PullRequestNumbers: result.Activity.PendingHeads,
		})
	}
	for start := 0; start < len(requests); start += queryBatchSize {
		batch := requests[start:min(start+queryBatchSize, len(requests))]
		query, aliases := buildPullRequestHeadQuery(batch)
		output, err := c.run(ctx, query)
		if err != nil {
			setActivityMessage(results, batch, err.Error())
			continue
		}
		var response rawResponse
		if err := json.Unmarshal(output, &response); err != nil {
			setActivityMessage(results, batch, "decode GraphQL response: "+err.Error())
			continue
		}
		collector.observe(response.Data)
		errorsByAlias, globalErrors := graphQLErrors(response.Errors)
		for alias, request := range aliases {
			key := repositoryKey(request.Repository.GitHub)
			result := results[key]
			messages := append(append([]string{}, globalErrors...), errorsByAlias[alias]...)
			fields, found, decodeErr := decodeGraphQLData[map[string]json.RawMessage](response.Data, alias)
			head := RepositoryActivityResult{}
			switch {
			case decodeErr != nil:
				head.Error = "decode GitHub activity data: " + decodeErr.Error()
			case !found || fields == nil:
				head.Error = strings.Join(append(messages, "GitHub returned no repository data"), "; ")
			case len(messages) > 0:
				head.Error = strings.Join(messages, "; ")
			default:
				head = activityResultFromFields(*fields)
			}
			if head.Error != "" {
				result.Activity.Message = head.Error
			}
			for _, number := range request.PullRequestNumbers {
				result.Activity.PullRequestRuns = append(result.Activity.PullRequestRuns, head.PullRequestRuns[number]...)
			}
			results[key] = result
		}
	}
}

func setActivityMessage(results map[string]RepositoryResult, requests []ActivityRequest, message string) {
	for _, request := range requests {
		key := repositoryKey(request.Repository.GitHub)
		result := results[key]
		if result.Activity != nil {
			result.Activity.Message = message
			results[key] = result
		}
	}
}

func sortedKeys(results map[string]RepositoryResult) []string {
	keys := make([]string, 0, len(results))
	for key := range results {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func setActivityError(results map[string]RepositoryActivityResult, requests []ActivityRequest, message string) {
	for _, request := range requests {
		results[repositoryKey(request.Repository.GitHub)] = RepositoryActivityResult{Error: message}
	}
}

func activityResultFromFields(fields map[string]json.RawMessage) RepositoryActivityResult {
	result := RepositoryActivityResult{
		TipRuns:             []model.WorkflowRun{},
		Deployments:         []model.Deployment{},
		PullRequestRuns:     map[int][]model.WorkflowRun{},
		DroppedPullRequests: map[int]struct{}{},
	}
	branch, _, err := decodeGraphQLData[rawDefaultBranchRef](fields, "defaultBranchRef")
	if err != nil {
		return RepositoryActivityResult{Error: "decode GitHub default branch: " + err.Error()}
	}
	if branch != nil && branch.Target != nil {
		result.TipOID = branch.Target.OID
		result.TipRuns = mappedWorkflowRuns(
			branch.Target.CheckSuites, model.WorkflowRunScopeTip, 0, branch.Name, branch.Target.OID,
		)
	}
	deployments, _, err := decodeGraphQLData[rawDeploymentConnection](fields, "deployments")
	if err != nil {
		return RepositoryActivityResult{Error: "decode GitHub deployments: " + err.Error()}
	}
	result.Deployments = mappedDeployments(deployments)
	for key := range fields {
		if !strings.HasPrefix(key, activityPullRequestAlias) {
			continue
		}
		number, convErr := strconv.Atoi(strings.TrimPrefix(key, activityPullRequestAlias))
		if convErr != nil || number <= 0 {
			continue
		}
		pullRequest, _, decodeErr := decodeGraphQLData[rawActivityPullRequest](fields, key)
		if decodeErr != nil {
			return RepositoryActivityResult{Error: "decode GitHub pull request activity: " + decodeErr.Error()}
		}
		if pullRequest == nil || !strings.EqualFold(strings.TrimSpace(pullRequest.State), "OPEN") {
			result.DroppedPullRequests[number] = struct{}{}
			continue
		}
		runs := pullRequestHeadRuns(pullRequest.HeadCommits, number, pullRequest.HeadRefName, pullRequest.HeadRefOID)
		if runs == nil {
			runs = []model.WorkflowRun{}
		}
		result.PullRequestRuns[number] = runs
	}
	return result
}
