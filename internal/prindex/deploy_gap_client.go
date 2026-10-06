package prindex

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/model"
)

// DeployRequest asks for one repository's default-branch deploy history.
type DeployRequest struct {
	Repository    string
	DefaultBranch string
}

// DeployResult is one repository's deploy gaps. Error leaves the cached
// status in place.
type DeployResult struct {
	Pipelines    []model.DeployGap
	PullRequests []model.UndeployedPullRequest
	Error        string
}

type rawDeployRuns struct {
	WorkflowRuns []struct {
		Path       string    `json:"path"`
		Name       string    `json:"name"`
		Event      string    `json:"event"`
		Status     string    `json:"status"`
		Conclusion string    `json:"conclusion"`
		HTMLURL    string    `json:"html_url"`
		CreatedAt  time.Time `json:"created_at"`
		HeadCommit *struct {
			Timestamp time.Time `json:"timestamp"`
		} `json:"head_commit"`
	} `json:"workflow_runs"`
}

type rawMergedPull struct {
	Number   int        `json:"number"`
	Title    string     `json:"title"`
	HTMLURL  string     `json:"html_url"`
	MergedAt *time.Time `json:"merged_at"`
	Head     struct {
		Ref string `json:"ref"`
	} `json:"head"`
	User *struct {
		Login string `json:"login"`
	} `json:"user"`
}

// CheckDeploys reads each repository's recent default-branch runs through
// the REST API, which does not spend GraphQL points, and lists recently
// closed pull requests only for repositories with a behind pipeline.
func (c GitHubClient) CheckDeploys(ctx context.Context, requests []DeployRequest) map[string]DeployResult {
	results := make(map[string]DeployResult, len(requests))
	var mutex sync.Mutex
	var group sync.WaitGroup
	slots := make(chan struct{}, pullRequestConcurrency)
	for _, request := range requests {
		group.Add(1)
		go func() {
			defer group.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			result := c.checkDeploy(ctx, request)
			mutex.Lock()
			results[repositoryKey(request.Repository)] = result
			mutex.Unlock()
		}()
	}
	group.Wait()
	return results
}

func (c GitHubClient) checkDeploy(ctx context.Context, request DeployRequest) DeployResult {
	branch := url.QueryEscape(request.DefaultBranch)
	var runs rawDeployRuns
	endpoint := "repos/" + request.Repository + "/actions/runs?exclude_pull_requests=true&per_page=100&branch=" + branch
	if err := c.restGet(ctx, endpoint, &runs); err != nil {
		return DeployResult{Error: "deploy runs: " + err.Error()}
	}
	mapped := make([]deployRun, 0, len(runs.WorkflowRuns))
	for _, run := range runs.WorkflowRuns {
		next := deployRun{
			Path: run.Path, Name: run.Name, Event: run.Event, Status: run.Status,
			Conclusion: run.Conclusion, URL: run.HTMLURL, CreatedAt: run.CreatedAt,
		}
		if run.HeadCommit != nil {
			next.CommitAt = run.HeadCommit.Timestamp
		}
		mapped = append(mapped, next)
	}
	gaps, cutoff := deployGaps(mapped)
	if len(gaps) == 0 {
		return DeployResult{}
	}
	var pulls []rawMergedPull
	endpoint = "repos/" + request.Repository + "/pulls?state=closed&sort=updated&direction=desc&per_page=50&base=" + branch
	if err := c.restGet(ctx, endpoint, &pulls); err != nil {
		return DeployResult{Error: "merged pull requests: " + err.Error()}
	}
	merged := make([]mergedPullRequest, 0, len(pulls))
	for _, pull := range pulls {
		next := mergedPullRequest{
			Number: pull.Number, Title: pull.Title, URL: pull.HTMLURL,
			HeadRefName: pull.Head.Ref, MergedAt: pull.MergedAt,
		}
		if pull.User != nil {
			next.Author = pull.User.Login
		}
		merged = append(merged, next)
	}
	undeployed := undeployedPullRequests(merged, cutoff)
	return DeployResult{Pipelines: keepReportableGaps(gaps, undeployed), PullRequests: undeployed}
}

// keepReportableGaps drops skip-only gaps when nothing merged is waiting:
// a skipped run after a manual redeploy of the same commit is not a gap.
// A failed deploy stays reportable even when the tip came from a direct push.
func keepReportableGaps(gaps []model.DeployGap, undeployed []model.UndeployedPullRequest) []model.DeployGap {
	if len(undeployed) > 0 {
		return gaps
	}
	var kept []model.DeployGap
	for _, gap := range gaps {
		if gap.Conclusion != "SKIPPED" {
			kept = append(kept, gap)
		}
	}
	return kept
}

func (c GitHubClient) restGet(ctx context.Context, endpoint string, target any) error {
	if c.Runner == nil {
		return errors.New("GitHub command runner is not configured")
	}
	commandContext, cancel := context.WithTimeout(ctx, githubTimeout)
	defer cancel()
	output, err := c.Runner.Run(commandContext, "", "gh", "api", endpoint)
	if err != nil {
		var commandError *command.Error
		if errors.As(err, &commandError) && strings.TrimSpace(commandError.Stderr) != "" {
			return errors.New(strings.TrimSpace(commandError.Stderr))
		}
		return err
	}
	return json.Unmarshal(output, target)
}
