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
		ID:             fmt.Sprintf("%s#%d", github, pullRequest.Number),
		Number:         pullRequest.Number,
		Title:          pullRequest.Title,
		URL:            pullRequest.URL,
		HeadRefName:    pullRequest.HeadRefName,
		HeadRefOID:     pullRequest.HeadRefOID,
		BaseRefName:    strings.TrimSpace(pullRequest.BaseRefName),
		AuthorLogin:    actorLogin(pullRequest.Author),
		Labels:         namedValues(pullRequest.Labels, true),
		Assignees:      namedValues(pullRequest.Assignees, false),
		ReviewRequests: reviewRequestNames(pullRequest.ReviewRequests),
		ReviewDecision: strings.TrimSpace(pullRequest.ReviewDecision),
		Additions:      pullRequest.Additions,
		Deletions:      pullRequest.Deletions,
		ChangedFiles:   pullRequest.ChangedFiles,
		CommentCount:   commentCount(pullRequest.Comments),
		CIState:        ciState(pullRequest.Commits),
		Summary: glanceSummary(
			pullRequest.Title,
			pullRequest.BodyText,
			commitHeadlines(pullRequest.Commits),
		),
		IsDraft:                 pullRequest.IsDraft,
		HasMergeConflict:        mergeableIsConflicting(pullRequest.Mergeable),
		UnresolvedReviewThreads: &unresolvedReviewThreads,
		UpdatedAt:               pullRequest.UpdatedAt.UTC(),
	}
}

func mergeableIsConflicting(mergeable string) bool {
	return strings.EqualFold(strings.TrimSpace(mergeable), "CONFLICTING")
}

func actorLogin(actor *rawNamedActor) string {
	if actor == nil {
		return ""
	}
	if login := strings.TrimSpace(actor.Login); login != "" {
		return login
	}
	return strings.TrimSpace(actor.Name)
}

func namedValues(nodes *rawNamedNodes, preferName bool) []string {
	if nodes == nil {
		return nil
	}
	values := make([]string, 0, len(nodes.Nodes))
	for _, node := range nodes.Nodes {
		value := strings.TrimSpace(node.Login)
		if preferName || value == "" {
			if name := strings.TrimSpace(node.Name); name != "" {
				value = name
			}
		}
		if value != "" {
			values = append(values, value)
		}
	}
	if len(values) == 0 {
		return nil
	}
	return values
}

func reviewRequestNames(requests *rawReviewRequestConnection) []string {
	if requests == nil {
		return nil
	}
	values := make([]string, 0, len(requests.Nodes))
	for _, node := range requests.Nodes {
		if name := actorLogin(node.RequestedReviewer); name != "" {
			values = append(values, name)
		}
	}
	if len(values) == 0 {
		return nil
	}
	return values
}

func commentCount(comments *rawCount) int {
	if comments == nil {
		return 0
	}
	return comments.TotalCount
}

func ciState(commits *rawCommitConnection) string {
	if commits == nil || len(commits.Nodes) == 0 {
		return ""
	}
	rollup := commits.Nodes[len(commits.Nodes)-1].Commit.StatusCheckRollup
	if rollup == nil {
		return ""
	}
	return strings.TrimSpace(rollup.State)
}
