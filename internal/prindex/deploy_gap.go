package prindex

import (
	"path"
	"sort"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

// deployRun is one default-branch Actions run as the REST runs listing
// reports it. CommitAt is the head commit timestamp, which equals the merge
// time of the pull request that produced a squash or merge commit.
type deployRun struct {
	Path       string
	Name       string
	Event      string
	Status     string
	Conclusion string
	URL        string
	CreatedAt  time.Time
	CommitAt   time.Time
}

// mergedPullRequest is one closed pull request from the REST pulls listing.
type mergedPullRequest struct {
	Number      int
	Title       string
	URL         string
	HeadRefName string
	Author      string
	MergedAt    *time.Time
}

const undeployedPullRequestLimit = 100

// mergeCommitSlack absorbs the second or so between a merge commit's
// timestamp and the pull request's merged_at, so the deployed pull request
// is not listed as undeployed.
const mergeCommitSlack = 10 * time.Second

// deployAttemptMaxAge retires a pipeline whose newest attempt is older than
// this: a deploy nobody has run in a month is retired, not behind.
const deployAttemptMaxAge = 30 * 24 * time.Hour

// deployGaps finds behind deploy pipelines in default-branch runs. A pipeline
// is behind when an automatic attempt after its last success did not
// deploy. Without a success in the window only a real failure counts, so a
// conditional workflow that always skips is never flagged. A pipeline whose
// newest attempt is older than deployAttemptMaxAge before now is retired and
// dropped before the cutoff is chosen; a zero now keeps every pipeline. The
// cutoff is the oldest last-success commit time across the remaining behind
// pipelines; zero when unknown.
func deployGaps(runs []deployRun, now time.Time) ([]model.DeployGap, time.Time) {
	runs = append([]deployRun(nil), runs...)
	sort.SliceStable(runs, func(i, j int) bool { return runs[i].CreatedAt.After(runs[j].CreatedAt) })
	byFile := map[string][]deployRun{}
	var order []string
	for _, run := range runs {
		if isPullRequestEvent(run.Event) || ClassifyPipeline(run.Path, run.Name) != model.PipelineAlertKindDeploy {
			continue
		}
		file := path.Base(run.Path)
		if _, seen := byFile[file]; !seen {
			order = append(order, file)
		}
		byFile[file] = append(byFile[file], run)
	}
	var gaps []model.DeployGap
	var cutoff time.Time
	for _, file := range order {
		gap, since, behind := pipelineGap(file, byFile[file])
		if !behind || (!now.IsZero() && now.Sub(gap.AttemptAt) > deployAttemptMaxAge) {
			continue
		}
		gaps = append(gaps, gap)
		if cutoff.IsZero() || since.Before(cutoff) {
			cutoff = since
		}
	}
	return gaps, cutoff
}

func pipelineGap(file string, runs []deployRun) (model.DeployGap, time.Time, bool) {
	var attempt *deployRun
	var oldestFailure *deployRun
	for index := range runs {
		run := &runs[index]
		if !strings.EqualFold(run.Status, "completed") {
			if attempt == nil {
				return model.DeployGap{}, time.Time{}, false
			}
			continue
		}
		conclusion := strings.ToUpper(run.Conclusion)
		if isSuccessfulConclusion(conclusion) {
			if attempt == nil {
				return model.DeployGap{}, time.Time{}, false
			}
			success := run.CommitAt
			if success.IsZero() {
				success = run.CreatedAt
			}
			gap := gapFromRun(file, *attempt)
			gap.LastSuccessAt = &success
			return gap, success.Add(mergeCommitSlack), true
		}
		failed := isFailedConclusion(conclusion) || conclusion == "CANCELLED"
		skipped := conclusion == "SKIPPED" && isAutomaticEvent(run.Event)
		if !failed && !skipped {
			continue
		}
		if attempt == nil {
			attempt = run
		}
		if failed {
			oldestFailure = run
		}
	}
	if attempt == nil || oldestFailure == nil {
		return model.DeployGap{}, time.Time{}, false
	}
	since := oldestFailure.CommitAt
	if since.IsZero() {
		since = oldestFailure.CreatedAt
	}
	return gapFromRun(file, *attempt), since.Add(-time.Second), true
}

func gapFromRun(file string, run deployRun) model.DeployGap {
	name := strings.TrimSpace(run.Name)
	if name == "" {
		name = workflowDisplayName(file)
	}
	return model.DeployGap{
		File: file, Name: name, Conclusion: strings.ToUpper(run.Conclusion),
		URL: run.URL, AttemptAt: run.CreatedAt.UTC(),
	}
}

func isPullRequestEvent(event string) bool {
	switch strings.ToLower(strings.TrimSpace(event)) {
	case "pull_request", "pull_request_target", "merge_group":
		return true
	}
	return false
}

func isAutomaticEvent(event string) bool {
	switch strings.ToLower(strings.TrimSpace(event)) {
	case "push", "workflow_run", "dynamic":
		return true
	}
	return false
}

// undeployedPullRequests keeps pull requests merged after cutoff, newest
// first. A zero cutoff keeps none: without a known boundary every merge
// would look undeployed.
func undeployedPullRequests(pulls []mergedPullRequest, cutoff time.Time) []model.UndeployedPullRequest {
	if cutoff.IsZero() {
		return nil
	}
	var kept []model.UndeployedPullRequest
	for _, pull := range pulls {
		if pull.MergedAt == nil || !pull.MergedAt.After(cutoff) {
			continue
		}
		kept = append(kept, model.UndeployedPullRequest{
			Number: pull.Number, Title: strings.TrimSpace(pull.Title), URL: pull.URL,
			HeadRefName: pull.HeadRefName, Author: pull.Author, MergedAt: pull.MergedAt.UTC(),
		})
	}
	sort.SliceStable(kept, func(i, j int) bool { return kept[i].MergedAt.After(kept[j].MergedAt) })
	if len(kept) > undeployedPullRequestLimit {
		kept = kept[:undeployedPullRequestLimit]
	}
	return kept
}

func cloneDeployStatus(status *model.DeployStatus) *model.DeployStatus {
	if status == nil {
		return nil
	}
	cloned := *status
	cloned.Pipelines = append([]model.DeployGap(nil), status.Pipelines...)
	cloned.PullRequests = append([]model.UndeployedPullRequest(nil), status.PullRequests...)
	return &cloned
}
