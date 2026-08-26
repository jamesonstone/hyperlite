package prindex

import (
	"fmt"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func mappedPullRequest(
	github string,
	pullRequest rawPullRequest,
	unresolvedReviewThreads int,
) model.ProjectPullRequest {
	return model.ProjectPullRequest{
		ID:                      fmt.Sprintf("%s#%d", github, pullRequest.Number),
		Number:                  pullRequest.Number,
		Title:                   pullRequest.Title,
		URL:                     pullRequest.URL,
		HeadRefName:             pullRequest.HeadRefName,
		HeadRefOID:              pullRequest.HeadRefOID,
		IsDraft:                 pullRequest.IsDraft,
		HasMergeConflict:        mergeableIsConflicting(pullRequest.Mergeable),
		UnresolvedReviewThreads: &unresolvedReviewThreads,
		UpdatedAt:               pullRequest.UpdatedAt.UTC(),
	}
}

func mergeableIsConflicting(mergeable string) bool {
	return strings.EqualFold(strings.TrimSpace(mergeable), "CONFLICTING")
}
