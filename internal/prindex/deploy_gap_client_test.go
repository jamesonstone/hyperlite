package prindex

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

type deployHistoryRunner struct {
	queries  []string
	response any
}

func (r *deployHistoryRunner) Run(_ context.Context, _ string, _ string, args ...string) ([]byte, error) {
	r.queries = append(r.queries, strings.TrimPrefix(args[len(args)-1], "query="))
	return json.Marshal(r.response)
}

func historyCommit(at string, pull map[string]any, suites ...map[string]any) map[string]any {
	pulls := []map[string]any{}
	if pull != nil {
		pulls = append(pulls, pull)
	}
	return map[string]any{
		"committedDate":          at,
		"associatedPullRequests": map[string]any{"nodes": pulls},
		"checkSuites":            map[string]any{"nodes": suites},
	}
}

func deploySuite(conclusion, event, url, at string) map[string]any {
	return map[string]any{"status": "COMPLETED", "conclusion": conclusion, "workflowRun": map[string]any{
		"url": url, "event": event, "createdAt": at,
		"workflow": map[string]any{"name": "deploy", "resourcePath": ".github/workflows/deploy.yaml"},
	}}
}

func mergedPull(number int, at string) map[string]any {
	return map[string]any{"number": number, "title": "t", "url": "https://x/pull", "headRefName": "GH-1", "mergedAt": at,
		"author": map[string]any{"login": "jameson"}}
}

func historyResponse(commits ...map[string]any) map[string]any {
	return map[string]any{"data": map[string]any{"repository": map[string]any{"defaultBranchRef": map[string]any{
		"target": map[string]any{"history": map[string]any{"nodes": commits}},
	}}}}
}

func TestCheckDeploysReadsCommitHistory(t *testing.T) {
	runner := &deployHistoryRunner{response: historyResponse(
		historyCommit("2026-10-05T17:24:27Z", mergedPull(1140, "2026-10-05T17:24:28Z")),
		historyCommit("2026-10-05T15:16:35Z", mergedPull(1118, "2026-10-05T15:16:36Z"),
			deploySuite("SKIPPED", "workflow_run", "https://x/runs/3", "2026-10-05T15:21:15Z")),
		historyCommit("2026-10-02T19:26:12Z", mergedPull(1130, "2026-10-02T19:26:13Z"),
			deploySuite("SUCCESS", "workflow_run", "https://x/runs/2", "2026-10-02T19:30:30Z")),
		historyCommit("2026-10-01T20:08:13Z", mergedPull(1120, "2026-10-01T20:08:14Z"),
			deploySuite("SUCCESS", "workflow_run", "https://x/runs/1", "2026-10-01T20:12:34Z")),
	)}
	now := time.Date(2026, 10, 6, 12, 0, 0, 0, time.UTC)
	result := GitHubClient{Runner: runner}.checkDeploy(context.Background(), DeployRequest{Repository: "o/r"}, now)
	if result.Error != "" || len(result.Pipelines) != 1 || result.Pipelines[0].URL != "https://x/runs/3" {
		t.Fatalf("want one skipped pipeline, got %#v", result)
	}
	if len(result.PullRequests) != 2 || result.PullRequests[0].Number != 1140 || result.PullRequests[1].Number != 1118 {
		t.Fatalf("want the merges above the last successful deploy, got %#v", result.PullRequests)
	}
	if query := runner.queries[0]; !strings.Contains(query, `owner: "o", name: "r"`) || !strings.Contains(query, "appId: 15368") {
		t.Fatalf("unexpected query: %s", query)
	}
}

func TestCheckDeploysIgnoresRetiredPipelinesAndReportsErrors(t *testing.T) {
	now := time.Date(2026, 10, 6, 12, 0, 0, 0, time.UTC)
	retired := &deployHistoryRunner{response: historyResponse(
		historyCommit("2026-10-05T12:00:00Z", mergedPull(9, "2026-10-05T12:00:01Z")),
		historyCommit("2026-08-14T19:56:55Z", nil, deploySuite("FAILURE", "workflow_dispatch", "https://x/runs/2", "2026-08-14T19:56:55Z")),
		historyCommit("2026-06-15T15:06:10Z", nil, deploySuite("SUCCESS", "workflow_dispatch", "https://x/runs/1", "2026-06-15T15:06:10Z")),
	)}
	if result := (GitHubClient{Runner: retired}).checkDeploy(context.Background(), DeployRequest{Repository: "o/r"}, now); len(result.Pipelines) != 0 {
		t.Fatalf("a deploy last attempted over a month ago is retired, got %#v", result)
	}
	failing := &deployHistoryRunner{response: map[string]any{"errors": []map[string]any{{"message": "boom"}}}}
	if result := (GitHubClient{Runner: failing}).checkDeploy(context.Background(), DeployRequest{Repository: "o/r"}, now); result.Error != "deploy history: boom" {
		t.Fatalf("GraphQL errors must surface, got %#v", result)
	}
}
