package prindex

import (
	"strconv"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
)

const (
	// githubActionsAppID filters check suites to GitHub Actions runs.
	githubActionsAppID       = 15368
	checkSuitePageSize       = 10
	deploymentPageSize       = 5
	workflowsTreeExpression  = "HEAD:.github/workflows"
	maxActivityPullRequests  = 10
	activityRepositoryPrefix = "repository"
	activityPullRequestAlias = "pr"
)

type rawWorkflowRun struct {
	URL          string    `json:"url"`
	CreatedAt    time.Time `json:"createdAt"`
	UpdatedAt    time.Time `json:"updatedAt"`
	Event        string    `json:"event"`
	RunNumber    int       `json:"runNumber"`
	DisplayTitle string    `json:"displayTitle"`
	Workflow     struct {
		Name         string `json:"name"`
		ResourcePath string `json:"resourcePath"`
	} `json:"workflow"`
}

type rawCheckSuite struct {
	Status      string          `json:"status"`
	Conclusion  string          `json:"conclusion"`
	UpdatedAt   time.Time       `json:"updatedAt"`
	WorkflowRun *rawWorkflowRun `json:"workflowRun"`
}

type rawCheckSuiteConnection struct {
	Nodes []rawCheckSuite `json:"nodes"`
}

type rawActivityCommit struct {
	OID         string                   `json:"oid"`
	CheckSuites *rawCheckSuiteConnection `json:"checkSuites"`
}

type rawDefaultBranchRef struct {
	Name   string             `json:"name"`
	Target *rawActivityCommit `json:"target"`
}

type rawTreeOID struct {
	OID string `json:"oid"`
}

type rawDeployment struct {
	Environment string    `json:"environment"`
	State       string    `json:"state"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
	Ref         *struct {
		Name string `json:"name"`
	} `json:"ref"`
	Commit *struct {
		OID string `json:"oid"`
	} `json:"commit"`
	LatestStatus *struct {
		State  string `json:"state"`
		LogURL string `json:"logUrl"`
	} `json:"latestStatus"`
}

type rawDeploymentConnection struct {
	Nodes []rawDeployment `json:"nodes"`
}

type rawHeadCommitConnection struct {
	Nodes []struct {
		Commit rawActivityCommit `json:"commit"`
	} `json:"nodes"`
}

// ActivityRequest names one repository and the open pull requests whose head
// runs were active at the last observation.
type ActivityRequest struct {
	Repository         config.Repository
	PullRequestNumbers []int
}

func writeCheckSuiteSelection(query *strings.Builder, indent string) {
	query.WriteString(indent)
	// GitHub returns checkSuites oldest-first and offers no orderBy, so a
	// running suite is the most recent one. `last` keeps the newest suites in
	// the bounded page; run selection then picks the freshest by updatedAt.
	query.WriteString("checkSuites(last: ")
	query.WriteString(strconv.Itoa(checkSuitePageSize))
	query.WriteString(", filterBy: {appId: ")
	query.WriteString(strconv.Itoa(githubActionsAppID))
	query.WriteString("}) { nodes { status conclusion updatedAt\n")
	query.WriteString(indent)
	query.WriteString("  workflowRun { url createdAt updatedAt event runNumber displayTitle workflow { name resourcePath } } } }\n")
}

func writeRepositoryActivitySelections(query *strings.Builder, indent string) {
	query.WriteString(indent)
	query.WriteString("defaultBranchRef { name target { ... on Commit { oid\n")
	writeCheckSuiteSelection(query, indent+"  ")
	query.WriteString(indent)
	query.WriteString("} } }\n")
	query.WriteString(indent)
	query.WriteString("workflowsTree: object(expression: ")
	query.WriteString(strconv.Quote(workflowsTreeExpression))
	query.WriteString(") { oid }\n")
	query.WriteString(indent)
	query.WriteString("deployments(first: ")
	query.WriteString(strconv.Itoa(deploymentPageSize))
	query.WriteString(", orderBy: {field: CREATED_AT, direction: DESC}) { nodes {\n")
	query.WriteString(indent)
	query.WriteString("  environment state createdAt updatedAt ref { name } commit { oid } latestStatus { state logUrl } } }\n")
}

func writeHeadCommitSelection(query *strings.Builder, indent string) {
	query.WriteString(indent)
	query.WriteString("headCommits: commits(last: 1) { nodes { commit { oid\n")
	writeCheckSuiteSelection(query, indent+"  ")
	query.WriteString(indent)
	query.WriteString("} } }\n")
}

func writeRepositoryOpen(query *strings.Builder, alias string, repository config.Repository) {
	owner, name, _ := strings.Cut(repository.GitHub, "/")
	query.WriteString("  ")
	query.WriteString(alias)
	query.WriteString(": repository(owner: ")
	query.WriteString(strconv.Quote(owner))
	query.WriteString(", name: ")
	query.WriteString(strconv.Quote(name))
	query.WriteString(") {\n")
}

// buildWorkflowCatalogQuery reads workflow file contents for repositories
// whose workflows tree changed. It never selects pull requests.
func buildWorkflowCatalogQuery(
	repositories []config.Repository,
) (string, map[string]config.Repository) {
	var query strings.Builder
	query.WriteString("query {\n")
	aliases := make(map[string]config.Repository, len(repositories))
	for index, repository := range repositories {
		alias := activityRepositoryPrefix + strconv.Itoa(index)
		aliases[alias] = repository
		writeRepositoryOpen(&query, alias, repository)
		query.WriteString("    object(expression: ")
		query.WriteString(strconv.Quote(workflowsTreeExpression))
		query.WriteString(") { oid ... on Tree { entries { name type object { ... on Blob { text isTruncated } } } } }\n")
		query.WriteString("  }\n")
	}
	writeRateLimit(&query)
	query.WriteString("}\n")
	return query.String(), aliases
}

// buildActivityPollQuery refreshes only tip runs, deployments, and the head
// runs of pull requests that were active. It never lists pull requests or
// reads workflow files.
func buildActivityPollQuery(
	requests []ActivityRequest,
) (string, map[string]ActivityRequest) {
	return buildActivityQuery(requests, true)
}

// buildPullRequestHeadQuery reads head runs for pending pull requests after a
// batch. Selecting head check suites inside the batch multiplies GitHub's
// cost by the pull-request page size, so pending heads are fetched here.
func buildPullRequestHeadQuery(
	requests []ActivityRequest,
) (string, map[string]ActivityRequest) {
	return buildActivityQuery(requests, false)
}

func buildActivityQuery(
	requests []ActivityRequest,
	includeRepositoryState bool,
) (string, map[string]ActivityRequest) {
	var query strings.Builder
	query.WriteString("query {\n")
	aliases := make(map[string]ActivityRequest, len(requests))
	for index, request := range requests {
		alias := activityRepositoryPrefix + strconv.Itoa(index)
		aliases[alias] = request
		writeRepositoryOpen(&query, alias, request.Repository)
		if includeRepositoryState {
			query.WriteString("    defaultBranchRef { name target { ... on Commit { oid\n")
			writeCheckSuiteSelection(&query, "      ")
			query.WriteString("    } } }\n")
			query.WriteString("    deployments(first: ")
			query.WriteString(strconv.Itoa(deploymentPageSize))
			query.WriteString(", orderBy: {field: CREATED_AT, direction: DESC}) { nodes {\n")
			query.WriteString("      environment state createdAt updatedAt ref { name } commit { oid } latestStatus { state logUrl } } }\n")
		}
		for _, number := range boundedPullRequestNumbers(request.PullRequestNumbers) {
			query.WriteString("    ")
			query.WriteString(activityPullRequestAlias)
			query.WriteString(strconv.Itoa(number))
			query.WriteString(": pullRequest(number: ")
			query.WriteString(strconv.Itoa(number))
			query.WriteString(") { number state headRefName headRefOid\n")
			writeHeadCommitSelection(&query, "      ")
			query.WriteString("    }\n")
		}
		query.WriteString("  }\n")
	}
	writeRateLimit(&query)
	query.WriteString("}\n")
	return query.String(), aliases
}

func boundedPullRequestNumbers(numbers []int) []int {
	if len(numbers) <= maxActivityPullRequests {
		return numbers
	}
	return numbers[:maxActivityPullRequests]
}
