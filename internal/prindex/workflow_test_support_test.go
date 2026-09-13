package prindex

import (
	"context"

	"github.com/jamesonstone/hyperlite/internal/config"
)

type fakeWorkflowClient struct {
	catalogCalls [][]config.Repository
	catalogs     map[string]CatalogEntry
	pollCalls    [][]ActivityRequest
	poll         ActivityResult
	rateLimit    *GitHubRateLimit
}

func (f *fakeWorkflowClient) FetchCatalogs(
	_ context.Context,
	repositories []config.Repository,
) CatalogResult {
	f.catalogCalls = append(f.catalogCalls, append([]config.Repository(nil), repositories...))
	return CatalogResult{Repositories: f.catalogs, RateLimit: f.rateLimit}
}

func (f *fakeWorkflowClient) PollActivity(
	_ context.Context,
	requests []ActivityRequest,
) ActivityResult {
	f.pollCalls = append(f.pollCalls, append([]ActivityRequest(nil), requests...))
	result := f.poll
	if result.RateLimit == nil {
		result.RateLimit = f.rateLimit
	}
	return result
}

func checkSuite(file, name, status, conclusion string) map[string]any {
	return map[string]any{
		"status": status, "conclusion": conclusion, "updatedAt": "2026-09-12T20:00:00Z",
		"workflowRun": map[string]any{
			"url":       "https://github.com/owner/repo/actions/runs/1",
			"createdAt": "2026-09-12T19:58:00Z", "updatedAt": "2026-09-12T20:00:00Z",
			"event": "push", "runNumber": 7, "displayTitle": "Run " + name,
			"workflow": map[string]any{
				"name":         name,
				"resourcePath": "/owner/repo/actions/workflows/" + file,
			},
		},
	}
}

func withActivity(
	page map[string]any,
	tipOID, treeOID string,
	tipSuites []map[string]any,
	deployments []map[string]any,
) map[string]any {
	if tipSuites == nil {
		tipSuites = []map[string]any{}
	}
	if deployments == nil {
		deployments = []map[string]any{}
	}
	page["defaultBranchRef"] = map[string]any{
		"name": "main",
		"target": map[string]any{
			"oid":         tipOID,
			"checkSuites": map[string]any{"nodes": tipSuites},
		},
	}
	if treeOID != "" {
		page["workflowsTree"] = map[string]any{"oid": treeOID}
	} else {
		page["workflowsTree"] = nil
	}
	page["deployments"] = map[string]any{"nodes": deployments}
	return page
}

func deploymentNode(environment, state string) map[string]any {
	return map[string]any{
		"environment": environment, "state": state,
		"createdAt": "2026-09-12T19:50:00Z", "updatedAt": "2026-09-12T19:55:00Z",
		"ref": map[string]any{"name": "main"}, "commit": map[string]any{"oid": "tip-1"},
		"latestStatus": map[string]any{"state": state, "logUrl": "https://example.com/log"},
	}
}
