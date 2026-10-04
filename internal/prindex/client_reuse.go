package prindex

import (
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

// detailReuseWindow bounds how long cached pull-request details may stand in
// for a detail query when the probe shows the open set unchanged. CI rollups
// and mergeability can change without bumping a pull request's updatedAt, so
// details are re-read at least this often.
const detailReuseWindow = 15 * time.Minute

// ListingHint is a repository's cached open set. When the probe reports the
// same open count and newest updatedAt, the cached details are reused and the
// detail query, by far the most expensive request, is skipped.
type ListingHint struct {
	OpenCount       int
	LatestUpdatedAt time.Time
	PullRequests    []model.ProjectPullRequest
	PullRequestRuns []model.WorkflowRun
}

func listingHint(entry cacheEntry, now time.Time) (ListingHint, bool) {
	if entry.LastError != "" || entry.DetailCheckedAt.IsZero() ||
		now.Sub(entry.DetailCheckedAt) >= detailReuseWindow ||
		len(entry.PullRequests) == 0 || cacheEntryNeedsHydration(entry) {
		return ListingHint{}, false
	}
	hint := ListingHint{OpenCount: len(entry.PullRequests)}
	for _, pullRequest := range entry.PullRequests {
		// A pending rollup will settle without bumping updatedAt.
		if isPendingRollup(pullRequest.CIState) {
			return ListingHint{}, false
		}
		if pullRequest.UpdatedAt.After(hint.LatestUpdatedAt) {
			hint.LatestUpdatedAt = pullRequest.UpdatedAt
		}
	}
	hint.PullRequests = append([]model.ProjectPullRequest(nil), entry.PullRequests...)
	if entry.Workflows != nil {
		for _, run := range entry.Workflows.Runs {
			if run.Scope == model.WorkflowRunScopePullRequest {
				hint.PullRequestRuns = append(hint.PullRequestRuns, run)
			}
		}
	}
	return hint, true
}

func (h ListingHint) matches(probe *rawOpenPullRequestProbe) bool {
	return probe != nil && probe.TotalCount == h.OpenCount && len(probe.Nodes) > 0 &&
		probe.Nodes[0].UpdatedAt.Equal(h.LatestUpdatedAt)
}

type rawOpenPullRequestProbe struct {
	TotalCount int `json:"totalCount"`
	Nodes      []struct {
		UpdatedAt time.Time `json:"updatedAt"`
	} `json:"nodes"`
}
