package prindex

import "time"

type rawPullRequest struct {
	Number         int                         `json:"number"`
	Title          string                      `json:"title"`
	URL            string                      `json:"url"`
	HeadRefName    string                      `json:"headRefName"`
	HeadRefOID     string                      `json:"headRefOid"`
	BaseRefName    string                      `json:"baseRefName"`
	IsDraft        bool                        `json:"isDraft"`
	Mergeable      string                      `json:"mergeable"`
	UpdatedAt      time.Time                   `json:"updatedAt"`
	Additions      int                         `json:"additions"`
	Deletions      int                         `json:"deletions"`
	ChangedFiles   int                         `json:"changedFiles"`
	ReviewDecision string                      `json:"reviewDecision"`
	Author         *rawNamedActor              `json:"author"`
	Labels         *rawNamedNodes              `json:"labels"`
	Assignees      *rawNamedNodes              `json:"assignees"`
	Comments       *rawCount                   `json:"comments"`
	ReviewRequests *rawReviewRequestConnection `json:"reviewRequests"`
	Commits        *rawCommitConnection        `json:"commits"`
	ReviewThreads  *rawReviewThreadConnection  `json:"reviewThreads"`
}

type rawNamedActor struct {
	Login string `json:"login"`
	Name  string `json:"name"`
}

type rawNamedNodes struct {
	Nodes []rawNamedActor `json:"nodes"`
}

type rawCount struct {
	TotalCount int `json:"totalCount"`
}

type rawReviewRequestConnection struct {
	Nodes []struct {
		RequestedReviewer *rawNamedActor `json:"requestedReviewer"`
	} `json:"nodes"`
}

type rawCommitConnection struct {
	Nodes []struct {
		Commit struct {
			StatusCheckRollup *struct {
				State string `json:"state"`
			} `json:"statusCheckRollup"`
		} `json:"commit"`
	} `json:"nodes"`
}

type rawRepository struct {
	PullRequests struct {
		Nodes    []rawPullRequest `json:"nodes"`
		PageInfo struct {
			HasNextPage bool   `json:"hasNextPage"`
			EndCursor   string `json:"endCursor"`
		} `json:"pageInfo"`
	} `json:"pullRequests"`
}
