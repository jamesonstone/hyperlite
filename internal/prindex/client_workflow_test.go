package prindex

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestListOpenCollectsRepositoryActivity(t *testing.T) {
	runner := &graphQLRunner{respond: func(query string, call int) ([]byte, error) {
		if call == 2 {
			if strings.Contains(query, "pullRequests(") || !strings.Contains(query, "pr1: pullRequest(number: 1)") {
				return nil, errors.New("head follow-up must query only pending heads: " + query)
			}
			return responseJSON(map[string]any{"repository0": map[string]any{
				"pr1": map[string]any{
					"number": 1, "state": "OPEN", "headRefName": "GH-1", "headRefOid": "head-1",
					"headCommits": map[string]any{"nodes": []map[string]any{{
						"commit": map[string]any{
							"oid":         "head-1",
							"checkSuites": map[string]any{"nodes": []map[string]any{checkSuite("ci.yaml", "ci", "IN_PROGRESS", "")}},
						},
					}}},
				},
			}}, nil), nil
		}
		page := repositoryPage(1, false, "")
		nodes := page["pullRequests"].(map[string]any)["nodes"].([]map[string]any)
		nodes[0]["commits"] = map[string]any{"nodes": []map[string]any{{
			"commit": map[string]any{"messageHeadline": "wip", "statusCheckRollup": map[string]any{"state": "PENDING"}},
		}}}
		withActivity(page, "tip-1", "tree-1",
			[]map[string]any{checkSuite("deploy.yaml", "deploy", "COMPLETED", "SUCCESS")},
			[]map[string]any{deploymentNode("prod", "IN_PROGRESS")},
		)
		return responseJSON(map[string]any{
			"repository0": page,
			"repository1": withActivity(repositoryPage(2, false, ""), "", "", nil, nil),
		}, nil), nil
	}}
	client := GitHubClient{Runner: runner}
	result := client.ListOpen(context.Background(), []config.Repository{
		{GitHub: "owner/one"}, {GitHub: "owner/two"},
	})
	if runner.calls != 2 {
		t.Fatalf("calls = %d (batch plus one pending-head follow-up)", runner.calls)
	}
	one := result.Repositories["owner/one"]
	if one.Error != "" || one.Activity == nil {
		t.Fatalf("one = %#v", one)
	}
	if one.Activity.TipOID != "tip-1" || one.Activity.TreeOID != "tree-1" ||
		len(one.Activity.TipRuns) != 1 || one.Activity.TipRuns[0].File != "deploy.yaml" ||
		len(one.Activity.PullRequestRuns) != 1 || one.Activity.PullRequestRuns[0].PullRequestNumber != 1 ||
		one.Activity.PullRequestRuns[0].HeadOID != "head-1" ||
		len(one.Activity.Deployments) != 1 || !one.Activity.Deployments[0].IsActive() {
		t.Fatalf("activity = %#v", one.Activity)
	}
	two := result.Repositories["owner/two"]
	if two.Error != "" || two.Activity == nil || two.Activity.TreeOID != "" ||
		len(two.Activity.TipRuns) != 0 || len(two.Activity.Deployments) != 0 {
		t.Fatalf("two = %#v", two)
	}
}

func TestPollActivityRefreshesOnlyRequestedHeads(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		return responseJSONWithRateLimit(map[string]any{
			"repository0": map[string]any{
				"defaultBranchRef": map[string]any{
					"name": "main",
					"target": map[string]any{
						"oid":         "tip-2",
						"checkSuites": map[string]any{"nodes": []map[string]any{checkSuite("main.yaml", "main", "COMPLETED", "SUCCESS")}},
					},
				},
				"deployments": map[string]any{"nodes": []map[string]any{deploymentNode("prod", "SUCCESS")}},
				"pr7": map[string]any{
					"number": 7, "state": "OPEN", "headRefName": "GH-7", "headRefOid": "head-7b",
					"headCommits": map[string]any{"nodes": []map[string]any{{
						"commit": map[string]any{
							"oid":         "head-7b",
							"checkSuites": map[string]any{"nodes": []map[string]any{checkSuite("ci.yaml", "ci", "COMPLETED", "FAILURE")}},
						},
					}}},
				},
				"pr8": nil,
				"pr9": map[string]any{"number": 9, "state": "MERGED"},
			},
		}, nil, githubRateLimit(20, 1, 40)), nil
	}}
	client := GitHubClient{Runner: runner}
	result := client.PollActivity(context.Background(), []ActivityRequest{{
		Repository: config.Repository{GitHub: "owner/one"}, PullRequestNumbers: []int{7, 8, 9},
	}})
	if runner.calls != 1 {
		t.Fatalf("calls = %d", runner.calls)
	}
	repository := result.Repositories["owner/one"]
	if repository.Error != "" || repository.TipOID != "tip-2" || len(repository.TipRuns) != 1 {
		t.Fatalf("repository = %#v", repository)
	}
	runs := repository.PullRequestRuns[7]
	if len(runs) != 1 || runs[0].Conclusion != "FAILURE" || runs[0].HeadOID != "head-7b" {
		t.Fatalf("pr7 = %#v", runs)
	}
	if _, dropped := repository.DroppedPullRequests[8]; !dropped {
		t.Fatalf("pr8 should be dropped: %#v", repository)
	}
	if _, dropped := repository.DroppedPullRequests[9]; !dropped {
		t.Fatalf("merged pr9 should be dropped: %#v", repository)
	}
	if result.RateLimit == nil || result.RateLimit.Used != 20 {
		t.Fatalf("rate limit = %#v", result.RateLimit)
	}
}

func TestPollActivityScopesGraphQLErrorsToRepository(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		return responseJSON(map[string]any{
			"repository0": nil,
			"repository1": map[string]any{"defaultBranchRef": nil, "deployments": map[string]any{"nodes": []map[string]any{}}},
		}, []map[string]any{{"message": "not found", "path": []any{"repository0"}}}), nil
	}}
	result := GitHubClient{Runner: runner}.PollActivity(context.Background(), []ActivityRequest{
		{Repository: config.Repository{GitHub: "owner/one"}},
		{Repository: config.Repository{GitHub: "owner/two"}},
	})
	if result.Repositories["owner/one"].Error != "not found" {
		t.Fatalf("one = %#v", result.Repositories["owner/one"])
	}
	if two := result.Repositories["owner/two"]; two.Error != "" || two.TipOID != "" || len(two.TipRuns) != 0 {
		t.Fatalf("two = %#v", two)
	}
}
