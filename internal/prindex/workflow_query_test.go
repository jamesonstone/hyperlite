package prindex

import (
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestBuildQuerySelectsWorkflowActivity(t *testing.T) {
	query, _ := buildQuery([]pageRequest{{
		repository: config.Repository{GitHub: "owner/repo"}, page: 1,
	}})
	for _, want := range []string{
		"checkSuites(last: 10, filterBy: {appId: 15368})",
		`workflowsTree: object(expression: "HEAD:.github/workflows") { oid }`,
		"deployments(first: 5, orderBy: {field: CREATED_AT, direction: DESC})",
		"defaultBranchRef { name target { ... on Commit { oid",
		"workflowRun { url createdAt updatedAt event runNumber displayTitle workflow { name resourcePath } }",
	} {
		if !strings.Contains(query, want) {
			t.Fatalf("query missing %q:\n%s", want, query)
		}
	}
	// Per-pull-request head suites multiply GitHub's cost by the page size;
	// they must stay out of the batch (measured 162 vs 23 points).
	for _, forbidden := range []string{"... on Blob", "headCommits:"} {
		if strings.Contains(query, forbidden) {
			t.Fatalf("batch query must not contain %q:\n%s", forbidden, query)
		}
	}
}

func TestBuildQueryOmitsRepositoryActivityOnFollowUpPages(t *testing.T) {
	query, _ := buildQuery([]pageRequest{{
		repository: config.Repository{GitHub: "owner/repo"}, page: 2, cursor: "CURSOR",
	}})
	// repositoryActivityFromRaw reads repository activity only from the first
	// page, so follow-up pages must not pay for it again.
	for _, forbidden := range []string{
		"defaultBranchRef", "checkSuites(", "deployments(", "workflowsTree:",
	} {
		if strings.Contains(query, forbidden) {
			t.Fatalf("follow-up page must not contain %q:\n%s", forbidden, query)
		}
	}
	if !strings.Contains(query, `after: "CURSOR"`) {
		t.Fatalf("follow-up page must page pull requests:\n%s", query)
	}
}

func TestBuildPullRequestHeadQueryReadsOnlyHeads(t *testing.T) {
	query, _ := buildPullRequestHeadQuery([]ActivityRequest{{
		Repository: config.Repository{GitHub: "owner/repo"}, PullRequestNumbers: []int{4},
	}})
	if !strings.Contains(query, "pr4: pullRequest(number: 4)") || !strings.Contains(query, "headCommits: commits(last: 1)") {
		t.Fatalf("query = %s", query)
	}
	for _, forbidden := range []string{"defaultBranchRef", "deployments(", "pullRequests("} {
		if strings.Contains(query, forbidden) {
			t.Fatalf("head query must not contain %q:\n%s", forbidden, query)
		}
	}
}

func TestBuildWorkflowCatalogQueryReadsBlobsOnly(t *testing.T) {
	query, aliases := buildWorkflowCatalogQuery([]config.Repository{
		{GitHub: "owner/one"}, {GitHub: "owner/two"},
	})
	if len(aliases) != 2 || aliases["repository1"].GitHub != "owner/two" {
		t.Fatalf("aliases = %#v", aliases)
	}
	if !strings.Contains(query, "... on Tree { entries { name type object { ... on Blob { text isTruncated } } } }") ||
		!strings.Contains(query, "rateLimit { limit used remaining resetAt cost nodeCount }") {
		t.Fatalf("query = %s", query)
	}
	if strings.Contains(query, "pullRequests(") || strings.Contains(query, "checkSuites(") {
		t.Fatalf("catalog query must not list pull requests or runs:\n%s", query)
	}
}

func TestBuildActivityPollQueryIsMinimal(t *testing.T) {
	numbers := make([]int, 0, 12)
	for number := 1; number <= 12; number++ {
		numbers = append(numbers, number)
	}
	query, aliases := buildActivityPollQuery([]ActivityRequest{{
		Repository: config.Repository{GitHub: "owner/repo"}, PullRequestNumbers: numbers,
	}})
	if len(aliases) != 1 || len(aliases["repository0"].PullRequestNumbers) != 12 {
		t.Fatalf("aliases = %#v", aliases)
	}
	for _, want := range []string{
		"pr1: pullRequest(number: 1) { number state headRefName headRefOid",
		"pr10: pullRequest(number: 10)",
		"defaultBranchRef { name target { ... on Commit { oid",
		"deployments(first: 5",
		"rateLimit {",
	} {
		if !strings.Contains(query, want) {
			t.Fatalf("query missing %q:\n%s", want, query)
		}
	}
	for _, forbidden := range []string{"pr11:", "pullRequests(", "object(expression", "reviewThreads"} {
		if strings.Contains(query, forbidden) {
			t.Fatalf("poll query must not contain %q:\n%s", forbidden, query)
		}
	}
}
