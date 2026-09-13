package prindex

import (
	"context"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestChangedTreeWithoutCatalogResultRetriesNextRefresh(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	source, repository, store := activityFixture(now)
	client := &fakePullRequestClient{results: map[string]RepositoryResult{
		"owner/one": {PullRequests: []model.ProjectPullRequest{}, Activity: &repositoryActivity{TreeOID: "tree-2"}},
	}}
	scanner := activityScanner(repository, store, &fakeWorkflowClient{}, client, now)
	result, err := scanner.Scan(context.Background(), config.Config{Projects: []config.Source{source}}, RefreshForce)
	if err != nil {
		t.Fatal(err)
	}
	state := result.Projects[0].Workflows
	if state.TreeOID != "" || len(state.Catalog) != 1 {
		t.Fatalf("missing catalog result must keep the old catalog and clear the tree OID: %#v", state)
	}
}

func TestFullRefreshCatalogFailureKeepsOldCatalogAndRetriesLater(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	source, repository, store := activityFixture(now)
	client := &fakePullRequestClient{results: map[string]RepositoryResult{
		"owner/one": {PullRequests: []model.ProjectPullRequest{}, Activity: &repositoryActivity{TreeOID: "tree-2"}},
	}}
	workflows := &fakeWorkflowClient{catalogs: map[string]CatalogEntry{"owner/one": {Error: "boom"}}}
	scanner := activityScanner(repository, store, workflows, client, now)
	result, err := scanner.Scan(context.Background(), config.Config{Projects: []config.Source{source}}, RefreshForce)
	if err != nil {
		t.Fatal(err)
	}
	state := result.Projects[0].Workflows
	if state.Message != "boom" || state.TreeOID != "" || len(state.Catalog) != 1 || state.Catalog[0].Name != "ci" {
		t.Fatalf("workflows = %#v", state)
	}
	if result.Projects[0].Status != model.ProjectPullRequestsCurrent {
		t.Fatalf("catalog failure must not fail the repository: %#v", result.Projects[0])
	}
}

func TestLegacyEntryWithoutWorkflowsRefreshesInsideFloor(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	source, repository, store := activityFixture(now)
	entry := store.state.Repositories["owner/one"]
	entry.Workflows = nil
	store.state.Repositories["owner/one"] = entry
	client := &fakePullRequestClient{results: map[string]RepositoryResult{"owner/one": {PullRequests: []model.ProjectPullRequest{}}}}
	scanner := activityScanner(repository, store, &fakeWorkflowClient{}, client, now)
	result, err := scanner.Scan(context.Background(), config.Config{Projects: []config.Source{source}}, RefreshStale)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 1 || result.Projects[0].Workflows == nil || len(result.Projects[0].Workflows.Runs) != 0 {
		t.Fatalf("calls=%d workflows=%#v", client.calls, result.Projects[0].Workflows)
	}
}
