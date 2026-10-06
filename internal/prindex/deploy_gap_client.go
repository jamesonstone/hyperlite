package prindex

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

// DeployRequest asks for one repository's default-branch deploy history.
type DeployRequest struct {
	Repository string
}

// DeployResult is one repository's deploy gaps. Error leaves the cached
// status in place.
type DeployResult struct {
	Pipelines    []model.DeployGap
	PullRequests []model.UndeployedPullRequest
	Error        string
}

const (
	// deployHistoryDepth is how many default-branch commits are read.
	deployHistoryDepth = 50
	// deployAttemptMaxAge drops a pipeline whose newest attempt is older
	// than this: a deploy nobody has run in a month is retired, not behind.
	deployAttemptMaxAge = 30 * 24 * time.Hour
)

type rawDeployHistory struct {
	DefaultBranchRef *struct {
		Target *struct {
			History *struct {
				Nodes []rawDeployCommit `json:"nodes"`
			} `json:"history"`
		} `json:"target"`
	} `json:"defaultBranchRef"`
}

type rawDeployCommit struct {
	CommittedDate          time.Time `json:"committedDate"`
	AssociatedPullRequests struct {
		Nodes []rawDeployPullRequest `json:"nodes"`
	} `json:"associatedPullRequests"`
	CheckSuites struct {
		Nodes []rawDeploySuite `json:"nodes"`
	} `json:"checkSuites"`
}

type rawDeployPullRequest struct {
	Number      int        `json:"number"`
	Title       string     `json:"title"`
	URL         string     `json:"url"`
	HeadRefName string     `json:"headRefName"`
	MergedAt    *time.Time `json:"mergedAt"`
	Author      *struct {
		Login string `json:"login"`
	} `json:"author"`
}

type rawDeploySuite struct {
	Status      string `json:"status"`
	Conclusion  string `json:"conclusion"`
	WorkflowRun *struct {
		URL       string    `json:"url"`
		Event     string    `json:"event"`
		CreatedAt time.Time `json:"createdAt"`
		Workflow  struct {
			Name         string `json:"name"`
			ResourcePath string `json:"resourcePath"`
		} `json:"workflow"`
	} `json:"workflowRun"`
}

// CheckDeploys reads each repository's recent default-branch commits with
// their Actions check suites and merged pull requests in one GraphQL query
// (about one point). The REST runs listings are not used: after the
// 2026-10-05 Actions outage they served lagging, inconsistent pages that hid
// real deploy gaps, while commit check suites stayed current.
func (c GitHubClient) CheckDeploys(ctx context.Context, requests []DeployRequest) map[string]DeployResult {
	results := make(map[string]DeployResult, len(requests))
	var mutex sync.Mutex
	var group sync.WaitGroup
	slots := make(chan struct{}, pullRequestConcurrency)
	now := time.Now()
	for _, request := range requests {
		group.Add(1)
		go func() {
			defer group.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			result := c.checkDeploy(ctx, request, now)
			mutex.Lock()
			results[repositoryKey(request.Repository)] = result
			mutex.Unlock()
		}()
	}
	group.Wait()
	return results
}

func (c GitHubClient) checkDeploy(ctx context.Context, request DeployRequest, now time.Time) DeployResult {
	commits, err := c.deployHistory(ctx, request.Repository)
	if err != nil {
		return DeployResult{Error: "deploy history: " + err.Error()}
	}
	runs, merged := deployEvidence(commits)
	gaps, cutoff := deployGaps(runs)
	gaps = recentGaps(gaps, now)
	if len(gaps) == 0 {
		return DeployResult{}
	}
	undeployed := undeployedPullRequests(merged, cutoff)
	return DeployResult{Pipelines: keepReportableGaps(gaps, undeployed), PullRequests: undeployed}
}

func deployHistoryQuery(repository string) string {
	owner, name, _ := strings.Cut(repository, "/")
	return "query { repository(owner: " + strconv.Quote(owner) + ", name: " + strconv.Quote(name) + ") {" +
		" defaultBranchRef { target { ... on Commit { history(first: " + strconv.Itoa(deployHistoryDepth) + ") { nodes {" +
		" committedDate" +
		" associatedPullRequests(first: 1) { nodes { number title url headRefName mergedAt author { login } } }" +
		" checkSuites(first: 20, filterBy: {appId: " + strconv.Itoa(githubActionsAppID) + "}) { nodes { status conclusion" +
		" workflowRun { url event createdAt workflow { name resourcePath } } } }" +
		" } } } } } } }"
}

func (c GitHubClient) deployHistory(ctx context.Context, repository string) ([]rawDeployCommit, error) {
	output, err := c.run(ctx, deployHistoryQuery(repository))
	if err != nil {
		return nil, err
	}
	var response struct {
		Data struct {
			Repository *rawDeployHistory `json:"repository"`
		} `json:"data"`
		Errors []rawGraphQLError `json:"errors"`
	}
	if err := json.Unmarshal(output, &response); err != nil {
		return nil, err
	}
	if len(response.Errors) > 0 {
		return nil, errors.New(response.Errors[0].Message)
	}
	repo := response.Data.Repository
	if repo == nil || repo.DefaultBranchRef == nil || repo.DefaultBranchRef.Target == nil ||
		repo.DefaultBranchRef.Target.History == nil {
		return nil, nil
	}
	return repo.DefaultBranchRef.Target.History.Nodes, nil
}

// deployEvidence turns commits into deploy runs keyed to their commit time
// and the merged pull requests that produced them.
func deployEvidence(commits []rawDeployCommit) ([]deployRun, []mergedPullRequest) {
	var runs []deployRun
	var merged []mergedPullRequest
	seen := map[int]struct{}{}
	for _, commit := range commits {
		for _, suite := range commit.CheckSuites.Nodes {
			if run := suite.WorkflowRun; run != nil {
				runs = append(runs, deployRun{
					Path: run.Workflow.ResourcePath, Name: run.Workflow.Name, Event: run.Event,
					Status: suite.Status, Conclusion: suite.Conclusion, URL: run.URL,
					CreatedAt: run.CreatedAt, CommitAt: commit.CommittedDate,
				})
			}
		}
		for _, pull := range commit.AssociatedPullRequests.Nodes {
			if _, duplicate := seen[pull.Number]; duplicate || pull.MergedAt == nil {
				continue
			}
			seen[pull.Number] = struct{}{}
			next := mergedPullRequest{
				Number: pull.Number, Title: pull.Title, URL: pull.URL,
				HeadRefName: pull.HeadRefName, MergedAt: pull.MergedAt,
			}
			if pull.Author != nil {
				next.Author = pull.Author.Login
			}
			merged = append(merged, next)
		}
	}
	return runs, merged
}

func recentGaps(gaps []model.DeployGap, now time.Time) []model.DeployGap {
	var kept []model.DeployGap
	for _, gap := range gaps {
		if now.Sub(gap.AttemptAt) <= deployAttemptMaxAge {
			kept = append(kept, gap)
		}
	}
	return kept
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
