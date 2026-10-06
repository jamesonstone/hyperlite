package prindex

import (
	"context"
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

// CheckDeploys reads each repository's recent default-branch commits with
// their Actions check suites and merged pull requests through GraphQL
// (about one point per page of 50 commits). The REST runs listings are not used: after the
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
	commits, err := c.deployHistory(ctx, request.Repository, now)
	if err != nil {
		return DeployResult{Error: "deploy history: " + err.Error()}
	}
	runs, merged := deployEvidence(commits)
	gaps, cutoff := deployGaps(runs, now)
	if len(gaps) == 0 {
		return DeployResult{}
	}
	undeployed := undeployedPullRequests(merged, cutoff)
	return DeployResult{Pipelines: keepReportableGaps(gaps, undeployed), PullRequests: undeployed}
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
					Path: deployRunPath(run.Workflow.ResourcePath), Name: run.Workflow.Name, Event: run.Event,
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
