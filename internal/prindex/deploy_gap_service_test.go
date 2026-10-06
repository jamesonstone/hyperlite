package prindex

import (
	"context"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

type fakeDeployClient struct {
	calls   [][]DeployRequest
	results map[string]DeployResult
}

func (f *fakeDeployClient) CheckDeploys(_ context.Context, requests []DeployRequest) map[string]DeployResult {
	f.calls = append(f.calls, append([]DeployRequest(nil), requests...))
	return f.results
}

func deployActivity(tip string, deploys *model.DeployStatus) *model.ProjectWorkflowActivity {
	return &model.ProjectWorkflowActivity{
		Catalog: []model.WorkflowDefinition{{File: "deploy.yaml", Name: "deploy"}},
		Runs: []model.WorkflowRun{{
			File: "deploy.yaml", Name: "deploy", Scope: model.WorkflowRunScopeTip,
			Status: "COMPLETED", Conclusion: "SKIPPED", HeadOID: tip,
		}},
		TipOID: tip, DefaultBranch: "main", Deploys: deploys,
	}
}

func TestRefreshDeployGapsChecksOnlyChangedRepositories(t *testing.T) {
	now := deployBase
	unchanged := deployActivity("tip-a", nil)
	unchanged.Deploys = &model.DeployStatus{Fingerprint: deployFingerprint(unchanged), CheckedAt: now.Add(-time.Minute)}
	noDeploy := &model.ProjectWorkflowActivity{
		Catalog: []model.WorkflowDefinition{{File: "ci.yaml", Name: "ci"}}, DefaultBranch: "main",
		Deploys: &model.DeployStatus{Pipelines: []model.DeployGap{{File: "old"}}},
	}
	store := &memoryCacheStore{state: cacheState{Repositories: map[string]cacheEntry{
		"owner/moved":     {Workflows: deployActivity("tip-b", &model.DeployStatus{Fingerprint: "old", CheckedAt: now.Add(-time.Minute)})},
		"owner/unchanged": {Workflows: unchanged},
		"owner/nodeploy":  {Workflows: noDeploy},
	}}}
	client := &fakeDeployClient{results: map[string]DeployResult{"owner/moved": {
		Pipelines:    []model.DeployGap{{File: "deploy.yaml", Conclusion: "SKIPPED"}},
		PullRequests: []model.UndeployedPullRequest{{Number: 9}},
	}}}
	scanner := Scanner{Store: store, Deploys: client}
	repositories := []config.Repository{{GitHub: "owner/moved"}, {GitHub: "owner/unchanged"}, {GitHub: "owner/nodeploy"}}
	cache, err := scanner.refreshDeployGaps(context.Background(), store.state, repositories, now)
	if err != nil {
		t.Fatal(err)
	}
	if len(client.calls) != 1 || len(client.calls[0]) != 1 || client.calls[0][0].Repository != "owner/moved" {
		t.Fatalf("only the moved tip should be checked: %#v", client.calls)
	}
	moved := cache.Repositories["owner/moved"].Workflows.Deploys
	if !moved.IsBehind() || moved.PullRequests[0].Number != 9 || moved.Fingerprint == "old" {
		t.Fatalf("moved repository should record its gap: %#v", moved)
	}
	if cache.Repositories["owner/nodeploy"].Workflows.Deploys != nil {
		t.Fatal("a repository without deploy pipelines should drop its stale status")
	}
}

func TestRefreshDeployGapsKeepsGapOnError(t *testing.T) {
	now := deployBase
	previous := &model.DeployStatus{Fingerprint: "old", Pipelines: []model.DeployGap{{File: "deploy.yaml"}}}
	store := &memoryCacheStore{state: cacheState{Repositories: map[string]cacheEntry{
		"owner/one": {Workflows: deployActivity("tip", previous)},
	}}}
	client := &fakeDeployClient{results: map[string]DeployResult{"owner/one": {Error: "HTTP 502"}}}
	cache, err := Scanner{Store: store, Deploys: client}.refreshDeployGaps(
		context.Background(), store.state, []config.Repository{{GitHub: "owner/one"}}, now,
	)
	if err != nil {
		t.Fatal(err)
	}
	status := cache.Repositories["owner/one"].Workflows.Deploys
	if !status.IsBehind() || status.Message != "HTTP 502" || status.Fingerprint != "old" {
		t.Fatalf("a failed check must keep the cached gap and retry later: %#v", status)
	}
}
