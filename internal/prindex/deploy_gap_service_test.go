package prindex

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
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
	if len(client.calls) != 1 || len(client.calls[0]) != 1 || client.calls[0][0] != (DeployRequest{Repository: "owner/moved", DefaultBranch: "main"}) {
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

type restRunner struct{ responses map[string]any }

func (r restRunner) Run(_ context.Context, _ string, name string, args ...string) ([]byte, error) {
	if name != "gh" || len(args) != 2 || args[0] != "api" {
		return nil, fmt.Errorf("unexpected command: %s %v", name, args)
	}
	for prefix, response := range r.responses {
		if strings.Contains(args[1], prefix) {
			return json.Marshal(response)
		}
	}
	return nil, fmt.Errorf("unexpected endpoint %s", args[1])
}

func TestCheckDeploysListsMergedPullRequestsSinceLastSuccess(t *testing.T) {
	runner := restRunner{responses: map[string]any{
		"/actions/runs?": map[string]any{"workflow_runs": []map[string]any{
			{"path": ".github/workflows/deploy.yaml", "name": "deploy", "event": "workflow_run", "status": "completed",
				"conclusion": "skipped", "html_url": "https://x/2", "created_at": "2026-10-05T16:44:06Z",
				"head_commit": map[string]any{"timestamp": "2026-10-05T16:41:03Z"}},
			{"path": ".github/workflows/deploy.yaml", "name": "deploy", "event": "workflow_run", "status": "completed",
				"conclusion": "success", "html_url": "https://x/1", "created_at": "2026-10-02T19:30:30Z",
				"head_commit": map[string]any{"timestamp": "2026-10-02T19:26:12Z"}},
		}},
		"/pulls?": []map[string]any{
			{"number": 12, "title": "ship", "html_url": "https://x/pull/12", "merged_at": "2026-10-05T16:41:03Z",
				"head": map[string]any{"ref": "GH-11"}, "user": map[string]any{"login": "jameson"}},
			{"number": 10, "title": "deployed", "merged_at": "2026-10-02T19:26:12Z", "head": map[string]any{"ref": "GH-9"}},
			{"number": 8, "title": "closed", "merged_at": nil, "head": map[string]any{"ref": "GH-7"}},
		},
	}}
	results := GitHubClient{Runner: runner}.CheckDeploys(
		context.Background(), []DeployRequest{{Repository: "Owner/One", DefaultBranch: "main"}},
	)
	result := results["owner/one"]
	if result.Error != "" || len(result.Pipelines) != 1 || result.Pipelines[0].URL != "https://x/2" {
		t.Fatalf("want one behind pipeline, got %#v", result)
	}
	if len(result.PullRequests) != 1 || result.PullRequests[0].Number != 12 || result.PullRequests[0].HeadRefName != "GH-11" {
		t.Fatalf("want only the pull request merged after the last deploy, got %#v", result.PullRequests)
	}
}

type pagedRunner func(endpoint string) any

func (r pagedRunner) Run(_ context.Context, _ string, _ string, args ...string) ([]byte, error) {
	return json.Marshal(r(args[1]))
}

func TestCheckDeploysPagesToLastSuccessAndCutoff(t *testing.T) {
	failure := func(at string) map[string]any {
		return map[string]any{"path": ".github/workflows/deploy.yaml", "name": "deploy", "event": "workflow_run",
			"status": "completed", "conclusion": "failure", "created_at": at, "head_commit": map[string]any{"timestamp": at}}
	}
	var pullPages []string
	runner := pagedRunner(func(endpoint string) any {
		switch {
		case strings.Contains(endpoint, "/actions/runs?") && strings.Contains(endpoint, "page=1&"):
			runs := make([]map[string]any, deployRunPageSize)
			for index := range runs {
				runs[index] = failure("2026-10-05T12:00:00Z")
			}
			return map[string]any{"workflow_runs": runs}
		case strings.Contains(endpoint, "/actions/runs?"):
			success := failure("2026-10-01T12:00:00Z")
			success["conclusion"] = "success"
			return map[string]any{"workflow_runs": []map[string]any{success}}
		case strings.Contains(endpoint, "page=1&"):
			pullPages = append(pullPages, endpoint)
			pulls := make([]map[string]any, mergedPullPageSize)
			for index := range pulls {
				pulls[index] = map[string]any{"number": 100 + index, "updated_at": "2026-10-05T12:00:00Z", "head": map[string]any{}}
			}
			return pulls
		default:
			pullPages = append(pullPages, endpoint)
			return []map[string]any{{"number": 7, "merged_at": "2026-10-02T12:00:00Z",
				"updated_at": "2026-10-02T12:00:00Z", "head": map[string]any{"ref": "GH-6"}}}
		}
	})
	result := GitHubClient{Runner: runner}.CheckDeploys(
		context.Background(), []DeployRequest{{Repository: "o/r", DefaultBranch: "main"}},
	)["o/r"]
	if len(result.Pipelines) != 1 || result.Pipelines[0].LastSuccessAt == nil {
		t.Fatalf("runs should page until the last success is found: %#v", result.Pipelines)
	}
	if len(pullPages) != 2 || len(result.PullRequests) != 1 || result.PullRequests[0].Number != 7 {
		t.Fatalf("pulls should page past recently updated PRs to the merge after cutoff: pages=%v prs=%#v", pullPages, result.PullRequests)
	}
}
