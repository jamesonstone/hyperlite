package prindex

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/model"
)

// DeployRequest asks for one repository's default-branch deploy history.
type DeployRequest struct {
	Repository    string
	DefaultBranch string
	// NewestRunAt is the newest default-branch tip run already observed
	// through GraphQL; a runs listing older than it is stale.
	NewestRunAt time.Time
}

// DeployResult is one repository's deploy gaps. Error leaves the cached
// status in place.
type DeployResult struct {
	Pipelines    []model.DeployGap
	PullRequests []model.UndeployedPullRequest
	Error        string
}

type rawDeployRuns struct {
	TotalCount   int            `json:"total_count"`
	WorkflowRuns []rawDeployRun `json:"workflow_runs"`
}

type rawDeployRun struct {
	Path       string    `json:"path"`
	Name       string    `json:"name"`
	Event      string    `json:"event"`
	Status     string    `json:"status"`
	Conclusion string    `json:"conclusion"`
	HTMLURL    string    `json:"html_url"`
	CreatedAt  time.Time `json:"created_at"`
	HeadCommit *struct {
		Timestamp time.Time `json:"timestamp"`
	} `json:"head_commit"`
}

type rawMergedPull struct {
	Number    int        `json:"number"`
	Title     string     `json:"title"`
	HTMLURL   string     `json:"html_url"`
	MergedAt  *time.Time `json:"merged_at"`
	UpdatedAt time.Time  `json:"updated_at"`
	Head      struct {
		Ref string `json:"ref"`
	} `json:"head"`
	User *struct {
		Login string `json:"login"`
	} `json:"user"`
}

// CheckDeploys reads each repository's recent default-branch runs through
// the REST API, which does not spend GraphQL points, and lists recently
// closed pull requests only for repositories with a behind pipeline.
func (c GitHubClient) CheckDeploys(ctx context.Context, requests []DeployRequest) map[string]DeployResult {
	results := make(map[string]DeployResult, len(requests))
	var mutex sync.Mutex
	var group sync.WaitGroup
	slots := make(chan struct{}, pullRequestConcurrency)
	for _, request := range requests {
		group.Add(1)
		go func() {
			defer group.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			result := c.checkDeploy(ctx, request)
			mutex.Lock()
			results[repositoryKey(request.Repository)] = result
			mutex.Unlock()
		}()
	}
	group.Wait()
	return results
}

const (
	deployRunPageSize  = 100
	deployRunMaxPages  = 3
	mergedPullPageSize = 50
	mergedPullMaxPages = 4
)

func (c GitHubClient) checkDeploy(ctx context.Context, request DeployRequest) DeployResult {
	branch := url.QueryEscape(request.DefaultBranch)
	runs, err := c.deployRuns(ctx, request.Repository, branch, request.NewestRunAt)
	if err != nil {
		return DeployResult{Error: "deploy runs: " + err.Error()}
	}
	gaps, cutoff := deployGaps(runs)
	if len(gaps) == 0 {
		return DeployResult{}
	}
	merged, err := c.mergedPullRequests(ctx, request.Repository, branch, cutoff)
	if err != nil {
		return DeployResult{Error: "merged pull requests: " + err.Error()}
	}
	undeployed := undeployedPullRequests(merged, cutoff)
	return DeployResult{Pipelines: keepReportableGaps(gaps, undeployed), PullRequests: undeployed}
}

// deployRuns pages default-branch runs until every behind pipeline has found
// its last success, so a busy repository whose first page is all newer than
// that success still gets the true cutoff. Paging stops at a short page or
// after deployRunMaxPages.
func (c GitHubClient) deployRuns(
	ctx context.Context,
	repository, branch string,
	newestKnown time.Time,
) ([]deployRun, error) {
	var mapped []deployRun
	for page := 1; page <= deployRunMaxPages; page++ {
		var runs rawDeployRuns
		endpoint := fmt.Sprintf(
			"repos/%s/actions/runs?exclude_pull_requests=true&per_page=%d&page=%d&branch=%s",
			repository, deployRunPageSize, page, branch,
		)
		if err := c.restGet(ctx, endpoint, &runs); err != nil {
			return nil, err
		}
		for _, run := range runs.WorkflowRuns {
			next := deployRun{
				Path: run.Path, Name: run.Name, Event: run.Event, Status: run.Status,
				Conclusion: run.Conclusion, URL: run.HTMLURL, CreatedAt: run.CreatedAt,
			}
			if run.HeadCommit != nil {
				next.CommitAt = run.HeadCommit.Timestamp
			}
			mapped = append(mapped, next)
		}
		if err := staleRunsPage(runs, page, mapped, newestKnown); err != nil {
			return nil, err
		}
		if len(runs.WorkflowRuns) < deployRunPageSize || !missingLastSuccess(mapped) {
			break
		}
	}
	return mapped, nil
}

// runListingSlack tolerates clock and indexing skew between the GraphQL tip
// observation and the REST runs listing.
const runListingSlack = 2 * time.Minute

// staleRunsPage rejects a listing GitHub served from a lagging index: a short
// page while total_count says more runs exist, or a first page whose newest
// run is older than a tip run already observed. One such page reported 40
// July runs for a repository with 204, which hid a real deploy gap.
func staleRunsPage(runs rawDeployRuns, page int, mapped []deployRun, newestKnown time.Time) error {
	seen := (page-1)*deployRunPageSize + len(runs.WorkflowRuns)
	if len(runs.WorkflowRuns) < deployRunPageSize && runs.TotalCount > seen {
		return fmt.Errorf("stale runs listing: page %d has %d of %d runs", page, len(runs.WorkflowRuns), runs.TotalCount)
	}
	if page != 1 || newestKnown.IsZero() {
		return nil
	}
	var newest time.Time
	for _, run := range mapped {
		if run.CreatedAt.After(newest) {
			newest = run.CreatedAt
		}
	}
	if newest.Add(runListingSlack).Before(newestKnown) {
		return fmt.Errorf("stale runs listing: newest run %s predates observed tip run %s",
			newest.UTC().Format(time.RFC3339), newestKnown.UTC().Format(time.RFC3339))
	}
	return nil
}

func missingLastSuccess(runs []deployRun) bool {
	gaps, _ := deployGaps(runs)
	for _, gap := range gaps {
		if gap.LastSuccessAt == nil {
			return true
		}
	}
	return false
}

// mergedPullRequests pages closed pull requests by most recent update until
// the page reaches updates older than cutoff. A merged pull request is never
// updated before it merged, so nothing past that point merged after cutoff.
func (c GitHubClient) mergedPullRequests(
	ctx context.Context,
	repository, branch string,
	cutoff time.Time,
) ([]mergedPullRequest, error) {
	var merged []mergedPullRequest
	for page := 1; page <= mergedPullMaxPages; page++ {
		var pulls []rawMergedPull
		endpoint := fmt.Sprintf(
			"repos/%s/pulls?state=closed&sort=updated&direction=desc&per_page=%d&page=%d&base=%s",
			repository, mergedPullPageSize, page, branch,
		)
		if err := c.restGet(ctx, endpoint, &pulls); err != nil {
			return nil, err
		}
		for _, pull := range pulls {
			next := mergedPullRequest{
				Number: pull.Number, Title: pull.Title, URL: pull.HTMLURL,
				HeadRefName: pull.Head.Ref, MergedAt: pull.MergedAt,
			}
			if pull.User != nil {
				next.Author = pull.User.Login
			}
			merged = append(merged, next)
		}
		if len(pulls) < mergedPullPageSize || pulls[len(pulls)-1].UpdatedAt.Before(cutoff) {
			break
		}
	}
	return merged, nil
}

// keepReportableGaps drops skip-only gaps when nothing merged is waiting:
// a skipped run after a manual redeploy of the same commit is not a gap.
// A failed deploy stays reportable even when the tip came from a direct push.
func keepReportableGaps(gaps []model.DeployGap, undeployed []model.UndeployedPullRequest) []model.DeployGap {
	if len(undeployed) > 0 {
		return gaps
	}
	var kept []model.DeployGap
	for _, gap := range gaps {
		if gap.Conclusion != "SKIPPED" {
			kept = append(kept, gap)
		}
	}
	return kept
}

func (c GitHubClient) restGet(ctx context.Context, endpoint string, target any) error {
	if c.Runner == nil {
		return errors.New("GitHub command runner is not configured")
	}
	commandContext, cancel := context.WithTimeout(ctx, githubTimeout)
	defer cancel()
	output, err := c.Runner.Run(commandContext, "", "gh", "api", endpoint)
	if err != nil {
		var commandError *command.Error
		if errors.As(err, &commandError) && strings.TrimSpace(commandError.Stderr) != "" {
			return errors.New(strings.TrimSpace(commandError.Stderr))
		}
		return err
	}
	return json.Unmarshal(output, target)
}
