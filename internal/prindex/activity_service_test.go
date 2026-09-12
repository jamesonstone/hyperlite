package prindex

import (
	"context"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func activityFixture(now time.Time) (config.Source, config.Repository, *memoryCacheStore) {
	source := config.Source{Path: "/repo/one"}
	repository := config.Repository{Name: "one", Path: source.Path, GitHub: "owner/one"}
	reviewThreads := 0
	observed := now.Add(-2 * time.Minute)
	store := &memoryCacheStore{state: cacheState{
		Version:  cacheVersion,
		Projects: map[string]string{source.Path: repository.GitHub},
		RateLimit: &model.GitHubRateLimit{
			Limit: 5000, Used: 100, Remaining: 4900, ResetAt: now.Add(40 * time.Minute),
			ObservedAt: observed, Cost: 1, NodeCount: 1,
		},
		Repositories: map[string]cacheEntry{
			"owner/one": {
				Repository: repository.GitHub, ObservedAt: observed, CheckedAt: observed,
				PullRequests: []model.ProjectPullRequest{{
					ID: "owner/one#7", Number: 7, Title: "Cached", HeadRefName: "GH-7", HeadRefOID: "head-7",
					UnresolvedReviewThreads: &reviewThreads,
				}},
				Workflows: &model.ProjectWorkflowActivity{
					Catalog: []model.WorkflowDefinition{{File: "ci.yaml", Name: "ci"}},
					Runs: []model.WorkflowRun{
						{File: "ci.yaml", Scope: model.WorkflowRunScopePullRequest, PullRequestNumber: 7, Status: "IN_PROGRESS"},
						{File: "main.yaml", Scope: model.WorkflowRunScopeTip, Status: "COMPLETED", Conclusion: "SUCCESS"},
					},
					Deployments: []model.Deployment{}, TreeOID: "tree-1",
					CheckedAt: &observed, ObservedAt: &observed,
				},
			},
		},
	}}
	return source, repository, store
}

func activityScanner(repository config.Repository, store *memoryCacheStore, workflows *fakeWorkflowClient, client *fakePullRequestClient, now time.Time) Scanner {
	return Scanner{
		Discovery: fakeProjectDiscoverer{result: discovery.Result{Repositories: []config.Repository{repository}}},
		Client:    client, Workflows: workflows, Store: store, Now: func() time.Time { return now },
	}
}

func TestActivityModePollsOnlyActiveHeadsAndNeverListsPullRequests(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	source, repository, store := activityFixture(now)
	workflows := &fakeWorkflowClient{
		poll: ActivityResult{Repositories: map[string]RepositoryActivityResult{
			"owner/one": {
				TipOID: "tip-2", TipRuns: []model.WorkflowRun{{File: "main.yaml", Scope: model.WorkflowRunScopeTip, Status: "IN_PROGRESS"}},
				Deployments: []model.Deployment{{Environment: "prod", State: "IN_PROGRESS"}},
				PullRequestRuns: map[int][]model.WorkflowRun{7: {{
					File: "ci.yaml", Scope: model.WorkflowRunScopePullRequest, PullRequestNumber: 7, Status: "COMPLETED", Conclusion: "SUCCESS",
				}}},
				DroppedPullRequests: map[int]struct{}{},
			},
		}},
		rateLimit: &GitHubRateLimit{Limit: 5000, Used: 101, Remaining: 4899, ResetAt: now.Add(40 * time.Minute), Cost: 1, NodeCount: 5},
	}
	client := &fakePullRequestClient{}
	scanner := activityScanner(repository, store, workflows, client, now)
	result, err := scanner.Scan(context.Background(), config.Config{Projects: []config.Source{source}}, RefreshActivity)
	if err != nil {
		t.Fatal(err)
	}
	if client.calls != 0 || len(workflows.pollCalls) != 1 || len(workflows.catalogCalls) != 0 {
		t.Fatalf("client=%d polls=%d catalogs=%d", client.calls, len(workflows.pollCalls), len(workflows.catalogCalls))
	}
	request := workflows.pollCalls[0][0]
	if request.Repository.GitHub != "owner/one" || len(request.PullRequestNumbers) != 1 || request.PullRequestNumbers[0] != 7 {
		t.Fatalf("request = %#v", request)
	}
	policy := result.ActivityPolicy
	if policy == nil || !policy.Allowed || policy.Reason != activityPollOK || policy.PollsThisWindow != 1 ||
		policy.LastCheckedAt == nil || !policy.LastCheckedAt.Equal(now) {
		t.Fatalf("policy = %#v", policy)
	}
	project := result.Projects[0]
	if project.Workflows == nil || project.Workflows.ObservedAt == nil || !project.Workflows.ObservedAt.Equal(now) ||
		project.Workflows.TreeOID != "tree-1" || len(project.Workflows.Catalog) != 1 ||
		project.Workflows.ActiveRunCount() != 2 || len(project.Workflows.Deployments) != 1 {
		t.Fatalf("workflows = %#v", project.Workflows)
	}
	if project.PullRequests[0].Number != 7 || project.Status != model.ProjectPullRequestsCurrent {
		t.Fatalf("rows must come from cache: %#v", project)
	}
	if result.RateLimit == nil || result.RateLimit.Used != 101 {
		t.Fatalf("rate limit = %#v", result.RateLimit)
	}
	if store.state.Activity == nil || store.state.Activity.PollsThisWindow != 1 || !store.state.Activity.LastCheckedAt.Equal(now) {
		t.Fatalf("activity state = %#v", store.state.Activity)
	}
}

func TestActivityModeDeniedTouchesNothing(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	source, repository, store := activityFixture(now)
	store.state.RateLimit.Remaining = 900
	store.state.RateLimit.Used = 4100
	workflows := &fakeWorkflowClient{}
	scanner := activityScanner(repository, store, workflows, &fakePullRequestClient{}, now)
	before := cloneCache(store.state)
	result, err := scanner.Scan(context.Background(), config.Config{Projects: []config.Source{source}}, RefreshActivity)
	if err != nil {
		t.Fatal(err)
	}
	if len(workflows.pollCalls) != 0 || store.state.UpdatedAt != before.UpdatedAt || store.state.Activity != nil {
		t.Fatalf("denied poll mutated state: polls=%d state=%#v", len(workflows.pollCalls), store.state.Activity)
	}
	if result.ActivityPolicy == nil || result.ActivityPolicy.Allowed || result.ActivityPolicy.Reason != activityPollQuotaFloor {
		t.Fatalf("policy = %#v", result.ActivityPolicy)
	}
}

func TestActivityModePollFailureKeepsObservedAtAndRecordsMessage(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	source, repository, store := activityFixture(now)
	workflows := &fakeWorkflowClient{poll: ActivityResult{Repositories: map[string]RepositoryActivityResult{
		"owner/one": {Error: "gh unavailable"},
	}}}
	scanner := activityScanner(repository, store, workflows, &fakePullRequestClient{}, now)
	result, err := scanner.Scan(context.Background(), config.Config{Projects: []config.Source{source}}, RefreshActivity)
	if err != nil {
		t.Fatal(err)
	}
	workflowsState := result.Projects[0].Workflows
	if workflowsState.Message != "gh unavailable" || workflowsState.CheckedAt == nil || !workflowsState.CheckedAt.Equal(now) ||
		workflowsState.ObservedAt == nil || workflowsState.ObservedAt.Equal(now) || workflowsState.ActiveRunCount() != 1 {
		t.Fatalf("workflows = %#v", workflowsState)
	}
}

func TestFullRefreshFetchesCatalogOnlyWhenTreeChanges(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	source, repository, store := activityFixture(now)
	activity := &repositoryActivity{TreeOID: "tree-1", TipOID: "tip-1"}
	client := &fakePullRequestClient{results: map[string]RepositoryResult{
		"owner/one": {PullRequests: []model.ProjectPullRequest{}, Activity: activity},
	}}
	workflows := &fakeWorkflowClient{catalogs: map[string]CatalogEntry{
		"owner/one": {TreeOID: "tree-2", Catalog: []model.WorkflowDefinition{{File: "ci.yaml", Name: "ci"}, {File: "deploy.yaml", Name: "deploy"}}},
	}}
	scanner := activityScanner(repository, store, workflows, client, now)
	cfg := config.Config{Projects: []config.Source{source}}
	first, err := scanner.Scan(context.Background(), cfg, RefreshForce)
	if err != nil {
		t.Fatal(err)
	}
	if len(workflows.catalogCalls) != 0 || len(first.Projects[0].Workflows.Catalog) != 1 {
		t.Fatalf("unchanged tree fetched catalog: calls=%d workflows=%#v", len(workflows.catalogCalls), first.Projects[0].Workflows)
	}
	if first.ActivityPolicy == nil || first.ActivityPolicy.Reason != activityPollNoActiveRuns || store.state.Activity != nil && !store.state.Activity.BurstStartedAt.IsZero() {
		t.Fatalf("policy = %#v activity = %#v", first.ActivityPolicy, store.state.Activity)
	}
	activity.TreeOID = "tree-2"
	activity.TipRuns = []model.WorkflowRun{{File: "deploy.yaml", Scope: model.WorkflowRunScopeTip, Status: "QUEUED"}}
	second, err := scanner.Scan(context.Background(), cfg, RefreshForce)
	if err != nil {
		t.Fatal(err)
	}
	if len(workflows.catalogCalls) != 1 || workflows.catalogCalls[0][0].GitHub != "owner/one" {
		t.Fatalf("catalog calls = %#v", workflows.catalogCalls)
	}
	state := second.Projects[0].Workflows
	if state.TreeOID != "tree-2" || len(state.Catalog) != 2 || state.ActiveRunCount() != 1 {
		t.Fatalf("workflows = %#v", state)
	}
	if store.state.Activity == nil || !store.state.Activity.BurstStartedAt.Equal(now) {
		t.Fatalf("burst not started: %#v", store.state.Activity)
	}
	if second.ActivityPolicy == nil || !second.ActivityPolicy.Allowed {
		t.Fatalf("policy = %#v", second.ActivityPolicy)
	}
}

func TestBurstClockRestartsForNewerWorkAndClosesOnPoll(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	source, repository, store := activityFixture(now)
	store.state.Activity = &cachedActivityState{BurstStartedAt: now.Add(-31 * time.Minute)}
	client := &fakePullRequestClient{results: map[string]RepositoryResult{
		"owner/one": {PullRequests: []model.ProjectPullRequest{}, Activity: &repositoryActivity{
			TreeOID: "tree-1",
			TipRuns: []model.WorkflowRun{{File: "deploy.yaml", Scope: model.WorkflowRunScopeTip, Status: "IN_PROGRESS", CreatedAt: now.Add(-time.Minute)}},
		}},
	}}
	workflows := &fakeWorkflowClient{poll: ActivityResult{Repositories: map[string]RepositoryActivityResult{
		"owner/one": {TipOID: "tip-1", TipRuns: []model.WorkflowRun{{File: "deploy.yaml", Scope: model.WorkflowRunScopeTip, Status: "COMPLETED", Conclusion: "SUCCESS"}},
			PullRequestRuns: map[int][]model.WorkflowRun{}, DroppedPullRequests: map[int]struct{}{}},
	}}}
	scanner := activityScanner(repository, store, workflows, client, now)
	cfg := config.Config{Projects: []config.Source{source}}
	refreshed, err := scanner.Scan(context.Background(), cfg, RefreshForce)
	if err != nil {
		t.Fatal(err)
	}
	if !store.state.Activity.BurstStartedAt.Equal(now) || refreshed.ActivityPolicy == nil || !refreshed.ActivityPolicy.Allowed {
		t.Fatalf("newer work must restart a stale burst: activity=%#v policy=%#v", store.state.Activity, refreshed.ActivityPolicy)
	}
	polled, err := scanner.Scan(context.Background(), cfg, RefreshActivity)
	if err != nil {
		t.Fatal(err)
	}
	if !store.state.Activity.BurstStartedAt.IsZero() || polled.Projects[0].Workflows.ActiveRunCount() != 0 {
		t.Fatalf("a poll observing completion must close the burst: %#v", store.state.Activity)
	}
}

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
