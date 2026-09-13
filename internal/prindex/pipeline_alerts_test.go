package prindex

import (
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestClassifyPipeline(t *testing.T) {
	cases := []struct {
		file, name, want string
	}{
		{"main.yaml", "Main", model.PipelineAlertKindMain},
		{"ci.yml", "CI", model.PipelineAlertKindMain},
		{"deploy.yaml", "Deploy", model.PipelineAlertKindDeploy},
		{"deploy-prod.yaml", "prod", model.PipelineAlertKindDeploy},
		{"codeql.yaml", "CodeQL", ""},
		{"ci-cd.yaml", "pipeline", ""},
	}
	for _, test := range cases {
		if got := ClassifyPipeline(test.file, test.name); got != test.want {
			t.Fatalf("ClassifyPipeline(%q, %q) = %q, want %q", test.file, test.name, got, test.want)
		}
	}
}

func TestReconcilePipelineAlertsPersistsTipFailure(t *testing.T) {
	now := time.Date(2026, 9, 13, 20, 0, 0, 0, time.UTC)
	failed := model.WorkflowRun{
		File: "main.yaml", Name: "main", Scope: model.WorkflowRunScopeTip,
		Status: "COMPLETED", Conclusion: "FAILURE", URL: "https://example.com/main",
		UpdatedAt: now.Add(-time.Hour),
	}
	alerts := ReconcilePipelineAlerts(nil, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{failed}}, now)
	if len(alerts) != 1 || alerts[0].Kind != model.PipelineAlertKindMain || alerts[0].URL != failed.URL {
		t.Fatalf("failed tip should set main: %#v", alerts)
	}
	prSuccess := model.WorkflowRun{
		File: "main.yaml", Name: "main", Scope: model.WorkflowRunScopePullRequest,
		Status: "COMPLETED", Conclusion: "SUCCESS", UpdatedAt: now,
	}
	kept := ReconcilePipelineAlerts(alerts, model.ProjectWorkflowActivity{
		Runs: []model.WorkflowRun{prSuccess},
	}, now)
	if len(kept) != 1 || kept[0].URL != failed.URL {
		t.Fatalf("pull-request success must not clear main: %#v", kept)
	}
	missing := ReconcilePipelineAlerts(alerts, model.ProjectWorkflowActivity{}, now)
	if len(missing) != 1 || missing[0].URL != failed.URL {
		t.Fatalf("missing observation must keep the cached failure: %#v", missing)
	}
	running := failed
	running.Status = "IN_PROGRESS"
	running.Conclusion = ""
	running.UpdatedAt = now
	still := ReconcilePipelineAlerts(alerts, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{running}}, now)
	if len(still) != 1 {
		t.Fatalf("an in-progress tip must not clear: %#v", still)
	}
	green := failed
	green.Conclusion = "SUCCESS"
	green.UpdatedAt = now
	if cleared := ReconcilePipelineAlerts(alerts, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{green}}, now); len(cleared) != 0 {
		t.Fatalf("green tip must clear main: %#v", cleared)
	}
}

func TestReconcilePipelineAlertsDeploySources(t *testing.T) {
	now := time.Date(2026, 9, 13, 20, 0, 0, 0, time.UTC)
	failedDeploy := model.WorkflowRun{
		File: "deploy.yaml", Name: "deploy", Scope: model.WorkflowRunScopeTip,
		Status: "COMPLETED", Conclusion: "FAILURE", URL: "https://example.com/deploy",
		UpdatedAt: now.Add(-time.Minute),
	}
	alerts := ReconcilePipelineAlerts(nil, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{failedDeploy}}, now)
	if len(alerts) != 1 || alerts[0].Kind != model.PipelineAlertKindDeploy {
		t.Fatalf("failed deploy workflow should set deploy: %#v", alerts)
	}
	envFail := model.Deployment{
		Environment: "prod", State: "FAILURE", LogURL: "https://example.com/log",
		UpdatedAt: now,
	}
	fromEnv := ReconcilePipelineAlerts(nil, model.ProjectWorkflowActivity{Deployments: []model.Deployment{envFail}}, now)
	if len(fromEnv) != 1 || fromEnv[0].URL != envFail.LogURL {
		t.Fatalf("failed environment should set deploy: %#v", fromEnv)
	}
	greenDeploy := failedDeploy
	greenDeploy.Conclusion = "SUCCESS"
	greenDeploy.UpdatedAt = now
	greenEnv := model.Deployment{
		Environment: "prod", State: "ACTIVE", LogURL: "https://example.com/log",
		UpdatedAt: now.Add(time.Minute),
	}
	cleared := ReconcilePipelineAlerts(fromEnv, model.ProjectWorkflowActivity{
		Runs:        []model.WorkflowRun{greenDeploy},
		Deployments: []model.Deployment{greenEnv},
	}, now)
	if len(cleared) != 0 {
		t.Fatalf("green deploy workflow and environment should clear: %#v", cleared)
	}
}

func TestReconcilePipelineAlertsMatchingSource(t *testing.T) {
	now := time.Date(2026, 9, 13, 20, 0, 0, 0, time.UTC)
	failed := model.WorkflowRun{
		File: "main.yaml", Name: "main", Scope: model.WorkflowRunScopeTip,
		Status: "COMPLETED", Conclusion: "FAILURE", URL: "https://example.com/main",
		UpdatedAt: now.Add(-time.Hour),
	}
	alerts := ReconcilePipelineAlerts(nil, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{failed}}, now)
	ciGreen := model.WorkflowRun{
		File: "ci.yml", Name: "CI", Scope: model.WorkflowRunScopeTip,
		Status: "COMPLETED", Conclusion: "SUCCESS", UpdatedAt: now,
	}
	kept := ReconcilePipelineAlerts(alerts, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{ciGreen}}, now)
	if len(kept) != 1 || kept[0].File != "main.yaml" {
		t.Fatalf("ci success must not clear main.yaml: %#v", kept)
	}
	green := failed
	green.Conclusion = "SUCCESS"
	green.UpdatedAt = now
	if cleared := ReconcilePipelineAlerts(alerts, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{green}}, now); len(cleared) != 0 {
		t.Fatalf("matching later success must clear: %#v", cleared)
	}
}

func TestReconcilePipelineAlertsChronology(t *testing.T) {
	now := time.Date(2026, 9, 13, 20, 0, 0, 0, time.UTC)
	cached := []model.PipelineAlert{{
		Kind: model.PipelineAlertKindMain, File: "main.yaml", Name: "main",
		Conclusion: "FAILURE", URL: "https://example.com/main", ObservedAt: now.Add(-time.Minute),
	}}
	olderGreen := model.WorkflowRun{
		File: "main.yaml", Name: "main", Scope: model.WorkflowRunScopeTip,
		Status: "COMPLETED", Conclusion: "SUCCESS", UpdatedAt: now.Add(-2 * time.Hour),
	}
	kept := ReconcilePipelineAlerts(cached, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{olderGreen}}, now)
	if len(kept) != 1 || kept[0].URL != cached[0].URL {
		t.Fatalf("older success must not clear: %#v", kept)
	}
	olderFail := olderGreen
	olderFail.Conclusion = "FAILURE"
	olderFail.URL = "https://example.com/old"
	replaced := ReconcilePipelineAlerts(cached, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{olderFail}}, now)
	if len(replaced) != 1 || replaced[0].URL != cached[0].URL {
		t.Fatalf("older failure must not replace: %#v", replaced)
	}
}

func TestReconcilePipelineAlertsDeployEnvDoesNotClearWorkflow(t *testing.T) {
	now := time.Date(2026, 9, 13, 20, 0, 0, 0, time.UTC)
	failed := model.WorkflowRun{
		File: "deploy.yaml", Name: "deploy", Scope: model.WorkflowRunScopeTip,
		Status: "COMPLETED", Conclusion: "FAILURE", URL: "https://example.com/deploy",
		UpdatedAt: now.Add(-time.Minute),
	}
	alerts := ReconcilePipelineAlerts(nil, model.ProjectWorkflowActivity{Runs: []model.WorkflowRun{failed}}, now)
	greenEnv := model.Deployment{
		Environment: "prod", State: "ACTIVE", LogURL: "https://example.com/log",
		UpdatedAt: now,
	}
	kept := ReconcilePipelineAlerts(alerts, model.ProjectWorkflowActivity{Deployments: []model.Deployment{greenEnv}}, now)
	if len(kept) != 1 || kept[0].File != "deploy.yaml" {
		t.Fatalf("env success without a deploy run must not clear: %#v", kept)
	}
}
