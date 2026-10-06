package prindex

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

type scriptedGraphQLRunner struct {
	queries   []string
	responses []any
}

func (r *scriptedGraphQLRunner) Run(_ context.Context, _ string, _ string, args ...string) ([]byte, error) {
	r.queries = append(r.queries, strings.TrimPrefix(args[len(args)-1], "query="))
	response := r.responses[min(len(r.queries), len(r.responses))-1]
	return json.Marshal(response)
}

func historyPage(hasNext bool, cursor string, commits ...map[string]any) map[string]any {
	response := historyResponse(commits...)
	history := response["data"].(map[string]any)["repository"].(map[string]any)["defaultBranchRef"].(map[string]any)["target"].(map[string]any)["history"].(map[string]any)
	history["pageInfo"] = map[string]any{"hasNextPage": hasNext, "endCursor": cursor}
	return response
}

func TestDeployHistoryPagesToTheLastSuccess(t *testing.T) {
	now := time.Date(2026, 12, 20, 12, 0, 0, 0, time.UTC)
	runner := &scriptedGraphQLRunner{responses: []any{
		historyPage(true, "c1",
			historyCommit("2026-12-19T12:00:00Z", mergedPull(5, "2026-12-19T12:00:01Z"),
				deploySuite("FAILURE", "workflow_run", "https://x/runs/9", "2026-12-19T12:05:00Z")),
			historyCommit("2026-11-01T12:00:00Z", mergedPull(4, "2026-11-01T12:00:01Z"))),
		historyPage(false, "",
			historyCommit("2026-10-01T12:00:00Z", mergedPull(3, "2026-10-01T12:00:01Z"),
				deploySuite("SUCCESS", "workflow_run", "https://x/runs/1", "2026-10-01T12:05:00Z"))),
	}}
	result := GitHubClient{Runner: runner}.checkDeploy(context.Background(), DeployRequest{Repository: "o/r"}, now)
	if len(runner.queries) != 2 || !strings.Contains(runner.queries[1], `after: "c1"`) {
		t.Fatalf("history should page past the window to the last success: %v", runner.queries)
	}
	if len(result.Pipelines) != 1 || result.Pipelines[0].LastSuccessAt == nil || len(result.PullRequests) != 2 {
		t.Fatalf("want the gap since the older success with both later merges, got %#v", result)
	}
}

func TestDeployHistoryCompletesOverflowingCheckSuites(t *testing.T) {
	now := time.Date(2026, 10, 6, 12, 0, 0, 0, time.UTC)
	busy := historyCommit("2026-10-05T12:00:00Z", mergedPull(8, "2026-10-05T12:00:01Z"))
	busy["oid"] = "abc"
	busy["checkSuites"] = map[string]any{"pageInfo": map[string]any{"hasNextPage": true, "endCursor": "s1"}, "nodes": []any{}}
	rest := map[string]any{"data": map[string]any{"repository": map[string]any{"object": map[string]any{"checkSuites": map[string]any{
		"pageInfo": map[string]any{"hasNextPage": false},
		"nodes":    []any{deploySuite("FAILURE", "workflow_run", "https://x/runs/2", "2026-10-05T12:05:00Z")},
	}}}}}
	older := historyCommit("2026-10-01T12:00:00Z", nil, deploySuite("SUCCESS", "workflow_run", "https://x/runs/1", "2026-10-01T12:05:00Z"))
	runner := &scriptedGraphQLRunner{responses: []any{historyPage(false, "", busy, older), rest}}
	result := GitHubClient{Runner: runner}.checkDeploy(context.Background(), DeployRequest{Repository: "o/r"}, now)
	if len(runner.queries) != 2 || !strings.Contains(runner.queries[1], `object(oid: "abc")`) || !strings.Contains(runner.queries[1], `after: "s1"`) {
		t.Fatalf("an overflowing commit should fetch its remaining suites: %v", runner.queries)
	}
	if len(result.Pipelines) != 1 || result.Pipelines[0].URL != "https://x/runs/2" {
		t.Fatalf("the deploy failure on the second suite page must count, got %#v", result)
	}
}

func TestDeployRunPathKeepsDynamicWorkflowsDistinct(t *testing.T) {
	cases := map[string]string{
		"/o/r/actions/workflows/deploy.yml":                    ".github/workflows/deploy.yml",
		"/o/r/actions/workflows/pages/pages-build-deployment":  "dynamic/pages/pages-build-deployment",
		"/o/r/actions/workflows/dependabot/dependabot-updates": "dynamic/dependabot/dependabot-updates",
	}
	for input, want := range cases {
		if got := deployRunPath(input); got != want {
			t.Fatalf("deployRunPath(%q) = %q, want %q", input, got, want)
		}
	}
	if ClassifyPipeline(deployRunPath("/o/r/actions/workflows/dependabot/dependabot-updates"), "pip in /deploy") != "" {
		t.Fatal("a GitHub-managed run named after a deploy folder must not classify as a deploy")
	}
}

func TestDeployHistoryStopsAtThePageCapWithTheFailureFallback(t *testing.T) {
	now := time.Date(2026, 10, 6, 12, 0, 0, 0, time.UTC)
	page := historyPage(true, "next",
		historyCommit("2026-10-05T12:00:00Z", mergedPull(2, "2026-10-05T12:00:01Z")),
		historyCommit("2026-10-04T12:00:00Z", mergedPull(1, "2026-10-04T12:00:01Z"),
			deploySuite("FAILURE", "workflow_run", "https://x/runs/1", "2026-10-04T12:05:00Z")))
	runner := &scriptedGraphQLRunner{responses: []any{page}}
	result := GitHubClient{Runner: runner}.checkDeploy(context.Background(), DeployRequest{Repository: "o/r"}, now)
	if len(runner.queries) != deployHistoryMaxPages {
		t.Fatalf("history must stop at %d pages, made %d queries", deployHistoryMaxPages, len(runner.queries))
	}
	if result.Error != "" || len(result.Pipelines) != 1 || result.Pipelines[0].LastSuccessAt != nil || len(result.PullRequests) != 2 {
		t.Fatalf("a capped walk reports the gap from the oldest observed failure, got %#v", result)
	}
}
