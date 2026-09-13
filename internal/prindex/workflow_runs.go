package prindex

import (
	"path"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/model"
)

// repositoryActivity is the Actions evidence observed alongside one
// repository's pull-request page. PendingHeads lists pull requests whose
// status rollup is still pending; their head runs come from one cheap
// follow-up query instead of a per-PR selection in the expensive batch.
type repositoryActivity struct {
	Repository      string
	TipOID          string
	TipRuns         []model.WorkflowRun
	PullRequestRuns []model.WorkflowRun
	Deployments     []model.Deployment
	TreeOID         string
	PendingHeads    []int
	Message         string
}

// repositoryActivityFromRaw sets repository-level activity once and collects
// pending pull requests from every page.
func repositoryActivityFromRaw(existing *repositoryActivity, raw *rawRepository, github string) *repositoryActivity {
	activity := existing
	if activity == nil {
		activity = &repositoryActivity{
			Repository: github,
			TipRuns:    []model.WorkflowRun{}, PullRequestRuns: []model.WorkflowRun{},
			Deployments: mappedDeployments(raw.Deployments),
		}
		if raw.DefaultBranchRef != nil && raw.DefaultBranchRef.Target != nil {
			activity.TipOID = raw.DefaultBranchRef.Target.OID
			activity.TipRuns = mappedWorkflowRuns(
				raw.DefaultBranchRef.Target.CheckSuites,
				model.WorkflowRunScopeTip, 0, raw.DefaultBranchRef.Name, raw.DefaultBranchRef.Target.OID,
			)
		}
		if raw.WorkflowsTree != nil {
			activity.TreeOID = raw.WorkflowsTree.OID
		}
	}
	for _, pullRequest := range raw.PullRequests.Nodes {
		if isPendingRollup(ciState(pullRequest.Commits)) {
			activity.PendingHeads = append(activity.PendingHeads, pullRequest.Number)
		}
	}
	return activity
}

func isPendingRollup(state string) bool {
	switch strings.ToUpper(strings.TrimSpace(state)) {
	case "PENDING", "EXPECTED":
		return true
	}
	return false
}

func pullRequestHeadRuns(
	commits *rawHeadCommitConnection,
	number int,
	headRefName, headOID string,
) []model.WorkflowRun {
	if commits == nil || len(commits.Nodes) == 0 {
		return nil
	}
	commit := commits.Nodes[len(commits.Nodes)-1].Commit
	return mappedWorkflowRuns(commit.CheckSuites, model.WorkflowRunScopePullRequest, number, headRefName, headOID)
}

func mappedWorkflowRuns(
	suites *rawCheckSuiteConnection,
	scope string,
	pullRequestNumber int,
	headRefName, headOID string,
) []model.WorkflowRun {
	if suites == nil {
		return nil
	}
	runs := make([]model.WorkflowRun, 0, len(suites.Nodes))
	for _, suite := range suites.Nodes {
		if suite.WorkflowRun == nil {
			continue
		}
		run := suite.WorkflowRun
		file := workflowFile(run.Workflow.ResourcePath)
		if file == "" {
			continue
		}
		name := strings.TrimSpace(run.Workflow.Name)
		if name == "" {
			name = workflowDisplayName(file)
		}
		runs = append(runs, model.WorkflowRun{
			File: file, Name: name, Scope: scope,
			PullRequestNumber: pullRequestNumber,
			HeadRefName:       strings.TrimSpace(headRefName),
			HeadOID:           strings.TrimSpace(headOID),
			Status:            strings.TrimSpace(suite.Status),
			Conclusion:        strings.TrimSpace(suite.Conclusion),
			Event:             strings.TrimSpace(run.Event),
			RunNumber:         run.RunNumber,
			DisplayTitle:      strings.TrimSpace(run.DisplayTitle),
			URL:               strings.TrimSpace(run.URL),
			CreatedAt:         run.CreatedAt.UTC(),
			UpdatedAt:         run.UpdatedAt.UTC(),
		})
	}
	return runs
}

func mappedDeployments(connection *rawDeploymentConnection) []model.Deployment {
	deployments := []model.Deployment{}
	if connection == nil {
		return deployments
	}
	for _, raw := range connection.Nodes {
		deployment := model.Deployment{
			Environment: strings.TrimSpace(raw.Environment),
			State:       strings.TrimSpace(raw.State),
			CreatedAt:   raw.CreatedAt.UTC(),
			UpdatedAt:   raw.UpdatedAt.UTC(),
		}
		if raw.Ref != nil {
			deployment.Ref = strings.TrimSpace(raw.Ref.Name)
		}
		if raw.Commit != nil {
			deployment.CommitOID = strings.TrimSpace(raw.Commit.OID)
		}
		if raw.LatestStatus != nil {
			deployment.LogURL = strings.TrimSpace(raw.LatestStatus.LogURL)
			if state := strings.TrimSpace(raw.LatestStatus.State); state != "" {
				deployment.State = state
			}
		}
		deployments = append(deployments, deployment)
	}
	return deployments
}

// workflowFile returns the join key for a run: the last path segment of the
// workflow resource path, such as "ci.yaml" or "codeql" for dynamic workflows.
func workflowFile(resourcePath string) string {
	trimmed := strings.TrimSpace(resourcePath)
	if trimmed == "" {
		return ""
	}
	file := path.Base(trimmed)
	if file == "." || file == "/" {
		return ""
	}
	return file
}

func workflowDisplayName(file string) string {
	name := strings.TrimSuffix(strings.TrimSuffix(file, ".yaml"), ".yml")
	return strings.TrimSpace(name)
}

// mergeActivityRuns replaces refreshed tip and pull-request runs while
// keeping runs for pull requests that were not part of the poll.
func mergeActivityRuns(
	existing []model.WorkflowRun,
	replaceTip bool,
	tipRuns []model.WorkflowRun,
	refreshed map[int][]model.WorkflowRun,
	dropped map[int]struct{},
) []model.WorkflowRun {
	merged := make([]model.WorkflowRun, 0, len(existing)+len(tipRuns))
	for _, run := range existing {
		switch run.Scope {
		case model.WorkflowRunScopeTip:
			if replaceTip {
				continue
			}
		case model.WorkflowRunScopePullRequest:
			if _, found := refreshed[run.PullRequestNumber]; found {
				continue
			}
			if _, gone := dropped[run.PullRequestNumber]; gone {
				continue
			}
		}
		merged = append(merged, run)
	}
	if replaceTip {
		merged = append(merged, tipRuns...)
	}
	for _, runs := range refreshed {
		merged = append(merged, runs...)
	}
	return merged
}
