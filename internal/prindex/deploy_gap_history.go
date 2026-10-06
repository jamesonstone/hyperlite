package prindex

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

const (
	deployHistoryPageSize = 50
	deployHistoryMaxPages = 4
	deploySuitePageSize   = 50
	deploySuiteMaxPages   = 4
)

type rawPageInfo struct {
	HasNextPage bool   `json:"hasNextPage"`
	EndCursor   string `json:"endCursor"`
}

type rawSuiteConnection struct {
	PageInfo rawPageInfo      `json:"pageInfo"`
	Nodes    []rawDeploySuite `json:"nodes"`
}

type rawDeployCommit struct {
	OID                    string    `json:"oid"`
	CommittedDate          time.Time `json:"committedDate"`
	AssociatedPullRequests struct {
		Nodes []rawDeployPullRequest `json:"nodes"`
	} `json:"associatedPullRequests"`
	CheckSuites rawSuiteConnection `json:"checkSuites"`
}

type rawDeployPullRequest struct {
	Number      int        `json:"number"`
	Title       string     `json:"title"`
	URL         string     `json:"url"`
	HeadRefName string     `json:"headRefName"`
	MergedAt    *time.Time `json:"mergedAt"`
	Author      *struct {
		Login string `json:"login"`
	} `json:"author"`
}

type rawDeploySuite struct {
	Status      string `json:"status"`
	Conclusion  string `json:"conclusion"`
	WorkflowRun *struct {
		URL       string    `json:"url"`
		Event     string    `json:"event"`
		CreatedAt time.Time `json:"createdAt"`
		Workflow  struct {
			Name         string `json:"name"`
			ResourcePath string `json:"resourcePath"`
		} `json:"workflow"`
	} `json:"workflowRun"`
}

const deploySuiteSelection = "pageInfo { hasNextPage endCursor } nodes { status conclusion" +
	" workflowRun { url event createdAt workflow { name resourcePath } } }"

func repositorySelector(repository string) string {
	owner, name, _ := strings.Cut(repository, "/")
	return "repository(owner: " + strconv.Quote(owner) + ", name: " + strconv.Quote(name) + ")"
}

func deployHistoryQuery(repository, after string) string {
	cursor := ""
	if after != "" {
		cursor = ", after: " + strconv.Quote(after)
	}
	return "query { " + repositorySelector(repository) + " {" +
		" defaultBranchRef { target { ... on Commit { history(first: " + strconv.Itoa(deployHistoryPageSize) + cursor + ") {" +
		" pageInfo { hasNextPage endCursor } nodes { oid committedDate" +
		" associatedPullRequests(first: 1) { nodes { number title url headRefName mergedAt author { login } } }" +
		" checkSuites(first: " + strconv.Itoa(deploySuitePageSize) + ", filterBy: {appId: " + strconv.Itoa(githubActionsAppID) + "}) { " +
		deploySuiteSelection + " } } } } } } } }"
}

func commitSuitesQuery(repository, oid, after string) string {
	return "query { " + repositorySelector(repository) + " { object(oid: " + strconv.Quote(oid) + ") { ... on Commit {" +
		" checkSuites(first: " + strconv.Itoa(deploySuitePageSize) + ", after: " + strconv.Quote(after) +
		", filterBy: {appId: " + strconv.Itoa(githubActionsAppID) + "}) { " + deploySuiteSelection + " } } } } }"
}

// deployHistory reads default-branch commits newest first, paging until the
// commits reach past the retirement window and every behind pipeline has a
// last success, and completes any commit whose check suites overflow a page
// so no deploy attempt is silently missing.
func (c GitHubClient) deployHistory(ctx context.Context, repository string, now time.Time) ([]rawDeployCommit, error) {
	var commits []rawDeployCommit
	after := ""
	for page := 1; page <= deployHistoryMaxPages; page++ {
		var data struct {
			Repository *struct {
				DefaultBranchRef *struct {
					Target *struct {
						History *struct {
							PageInfo rawPageInfo       `json:"pageInfo"`
							Nodes    []rawDeployCommit `json:"nodes"`
						} `json:"history"`
					} `json:"target"`
				} `json:"defaultBranchRef"`
			} `json:"repository"`
		}
		if err := c.graphQLData(ctx, deployHistoryQuery(repository, after), &data); err != nil {
			return nil, err
		}
		repo := data.Repository
		if repo == nil || repo.DefaultBranchRef == nil || repo.DefaultBranchRef.Target == nil ||
			repo.DefaultBranchRef.Target.History == nil {
			return commits, nil
		}
		history := repo.DefaultBranchRef.Target.History
		for _, commit := range history.Nodes {
			if err := c.completeSuites(ctx, repository, &commit); err != nil {
				return nil, err
			}
			commits = append(commits, commit)
		}
		if !history.PageInfo.HasNextPage || !needsOlderCommits(commits, now) {
			return commits, nil
		}
		after = history.PageInfo.EndCursor
	}
	// The page cap ended the walk with older commits still unread. This is a
	// deliberate, bounded result, not an error: every attempt in the newest
	// deployHistoryMaxPages*deployHistoryPageSize commits is present, and a
	// pipeline whose last success lies beyond them falls back to the cutoff
	// just before its oldest observed failure (pipelineGap). Reporting an
	// error instead would leave a busy repository permanently unchecked.
	return commits, nil
}

func needsOlderCommits(commits []rawDeployCommit, now time.Time) bool {
	if len(commits) == 0 {
		return false
	}
	if now.Sub(commits[len(commits)-1].CommittedDate) <= deployAttemptMaxAge {
		return true
	}
	runs, _ := deployEvidence(commits)
	gaps, _ := deployGaps(runs, now)
	for _, gap := range gaps {
		if gap.LastSuccessAt == nil {
			return true
		}
	}
	return false
}

func (c GitHubClient) completeSuites(ctx context.Context, repository string, commit *rawDeployCommit) error {
	for page := 1; commit.CheckSuites.PageInfo.HasNextPage; page++ {
		if page > deploySuiteMaxPages {
			return fmt.Errorf("commit %s has more than %d Actions check suites", commit.OID,
				deploySuitePageSize*(deploySuiteMaxPages+1))
		}
		var data struct {
			Repository *struct {
				Object *struct {
					CheckSuites rawSuiteConnection `json:"checkSuites"`
				} `json:"object"`
			} `json:"repository"`
		}
		query := commitSuitesQuery(repository, commit.OID, commit.CheckSuites.PageInfo.EndCursor)
		if err := c.graphQLData(ctx, query, &data); err != nil {
			return err
		}
		if data.Repository == nil || data.Repository.Object == nil {
			return fmt.Errorf("commit %s disappeared while reading its check suites", commit.OID)
		}
		next := data.Repository.Object.CheckSuites
		commit.CheckSuites.Nodes = append(commit.CheckSuites.Nodes, next.Nodes...)
		commit.CheckSuites.PageInfo = next.PageInfo
	}
	return nil
}

func (c GitHubClient) graphQLData(ctx context.Context, query string, target any) error {
	output, err := c.run(ctx, query)
	if err != nil {
		return err
	}
	var response struct {
		Data   json.RawMessage   `json:"data"`
		Errors []rawGraphQLError `json:"errors"`
	}
	if err := json.Unmarshal(output, &response); err != nil {
		return err
	}
	if len(response.Errors) > 0 {
		return errors.New(response.Errors[0].Message)
	}
	return json.Unmarshal(response.Data, target)
}

// deployRunPath maps a GraphQL workflow resourcePath such as
// /owner/repo/actions/workflows/deploy.yml to .github/workflows/deploy.yml,
// and a GitHub-managed /owner/repo/actions/workflows/pages/pages-build-deployment
// to dynamic/pages/pages-build-deployment, so ClassifyPipeline still sees the
// dynamic/ prefix that keeps per-run names out of classification.
func deployRunPath(resourcePath string) string {
	trimmed := strings.TrimSpace(resourcePath)
	_, rest, found := strings.Cut(trimmed, "/actions/workflows/")
	if !found {
		return trimmed
	}
	if strings.Contains(rest, "/") {
		return "dynamic/" + rest
	}
	return ".github/workflows/" + rest
}
