package prindex

import (
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestMappedWorkflowRunsSkipsNonActionsSuitesAndDerivesFile(t *testing.T) {
	created := time.Date(2026, 9, 12, 19, 58, 0, 0, time.UTC)
	suites := &rawCheckSuiteConnection{Nodes: []rawCheckSuite{
		{Status: "COMPLETED", Conclusion: "SUCCESS"},
		{Status: "IN_PROGRESS", WorkflowRun: &rawWorkflowRun{
			URL: "https://github.com/owner/repo/actions/runs/9", CreatedAt: created, Event: "push",
			RunNumber: 9, DisplayTitle: "deploy main",
			Workflow: struct {
				Name         string `json:"name"`
				ResourcePath string `json:"resourcePath"`
			}{Name: "deploy", ResourcePath: "/owner/repo/actions/workflows/deploy.yaml"},
		}},
		{Status: "COMPLETED", Conclusion: "SUCCESS", WorkflowRun: &rawWorkflowRun{
			Workflow: struct {
				Name         string `json:"name"`
				ResourcePath string `json:"resourcePath"`
			}{ResourcePath: "/owner/repo/actions/workflows/github-code-scanning/codeql"},
		}},
	}}
	runs := mappedWorkflowRuns(suites, model.WorkflowRunScopePullRequest, 12, "GH-12", "head-12")
	if len(runs) != 2 {
		t.Fatalf("runs = %#v", runs)
	}
	deploy := runs[0]
	if deploy.File != "deploy.yaml" || deploy.Name != "deploy" || !deploy.IsActive() ||
		deploy.PullRequestNumber != 12 || deploy.HeadRefName != "GH-12" || deploy.HeadOID != "head-12" ||
		deploy.Scope != model.WorkflowRunScopePullRequest || deploy.RunNumber != 9 ||
		!deploy.CreatedAt.Equal(created) {
		t.Fatalf("deploy = %#v", deploy)
	}
	if runs[1].File != "codeql" || runs[1].Name != "codeql" || runs[1].IsActive() {
		t.Fatalf("codeql = %#v", runs[1])
	}
}

func TestMappedDeploymentsPrefersLatestStatus(t *testing.T) {
	deployments := mappedDeployments(&rawDeploymentConnection{Nodes: []rawDeployment{{
		Environment: "prod", State: "ACTIVE",
		LatestStatus: &struct {
			State  string `json:"state"`
			LogURL string `json:"logUrl"`
		}{State: "IN_PROGRESS", LogURL: "https://example.com/log"},
	}}})
	if len(deployments) != 1 || deployments[0].State != "IN_PROGRESS" ||
		!deployments[0].IsActive() || deployments[0].LogURL != "https://example.com/log" {
		t.Fatalf("deployments = %#v", deployments)
	}
	if got := mappedDeployments(nil); got == nil || len(got) != 0 {
		t.Fatalf("nil connection = %#v", got)
	}
}

func TestMergeActivityRunsReplacesTipAndPolledPullRequests(t *testing.T) {
	existing := []model.WorkflowRun{
		{File: "main.yaml", Scope: model.WorkflowRunScopeTip, Status: "IN_PROGRESS"},
		{File: "ci.yaml", Scope: model.WorkflowRunScopePullRequest, PullRequestNumber: 1, Status: "IN_PROGRESS"},
		{File: "ci.yaml", Scope: model.WorkflowRunScopePullRequest, PullRequestNumber: 2, Status: "IN_PROGRESS"},
		{File: "ci.yaml", Scope: model.WorkflowRunScopePullRequest, PullRequestNumber: 3, Status: "COMPLETED"},
	}
	merged := mergeActivityRuns(
		existing, true,
		[]model.WorkflowRun{{File: "main.yaml", Scope: model.WorkflowRunScopeTip, Status: "COMPLETED"}},
		map[int][]model.WorkflowRun{1: {{File: "ci.yaml", Scope: model.WorkflowRunScopePullRequest, PullRequestNumber: 1, Status: "COMPLETED"}}},
		map[int]struct{}{2: {}},
	)
	if len(merged) != 3 {
		t.Fatalf("merged = %#v", merged)
	}
	byKey := map[string]model.WorkflowRun{}
	for _, run := range merged {
		byKey[run.Scope+"#"+string(rune('0'+run.PullRequestNumber))] = run
	}
	if byKey["tip#0"].Status != "COMPLETED" || byKey["pull_request#1"].Status != "COMPLETED" ||
		byKey["pull_request#3"].Status != "COMPLETED" {
		t.Fatalf("merged = %#v", merged)
	}
	if _, kept := byKey["pull_request#2"]; kept {
		t.Fatalf("dropped pull request retained: %#v", merged)
	}
	unchangedTip := mergeActivityRuns(existing, false, nil, nil, nil)
	if len(unchangedTip) != 4 || unchangedTip[0].Status != "IN_PROGRESS" {
		t.Fatalf("keeping the tip must retain tip runs: %#v", unchangedTip)
	}
	noBranch := mergeActivityRuns(existing, true, nil, nil, nil)
	if len(noBranch) != 3 || noBranch[0].Scope != model.WorkflowRunScopePullRequest {
		t.Fatalf("a poll without a default branch must drop stale tip runs: %#v", noBranch)
	}
}

func TestActiveRunHelpers(t *testing.T) {
	activity := model.ProjectWorkflowActivity{
		Runs: []model.WorkflowRun{
			{Status: "queued", PullRequestNumber: 4},
			{Status: "IN_PROGRESS", PullRequestNumber: 4},
			{Status: "COMPLETED", PullRequestNumber: 5},
			{Status: "WAITING"},
		},
		Deployments: []model.Deployment{{State: "PENDING"}, {State: "ACTIVE"}},
	}
	if activity.ActiveRunCount() != 4 {
		t.Fatalf("active = %d", activity.ActiveRunCount())
	}
	numbers := activity.ActivePullRequestNumbers()
	if len(numbers) != 1 || numbers[0] != 4 {
		t.Fatalf("numbers = %v", numbers)
	}
}
