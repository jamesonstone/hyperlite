package model

import "time"

type PublicationState string
type CIState string

const (
	PublicationBase       PublicationState = "base"
	PublicationNoUpstream PublicationState = "no_upstream"
	PublicationUnpushed   PublicationState = "unpushed"
	PublicationPublished  PublicationState = "published"
	PublicationBehind     PublicationState = "behind"
	PublicationDiverged   PublicationState = "diverged"
	PublicationUnknown    PublicationState = "unknown"

	CISuccess CIState = "success"
	CIPending CIState = "pending"
	CIFailure CIState = "failure"
	CINone    CIState = "none"
	CIUnknown CIState = "unknown"
)

type CheckSummary struct {
	Total   int `json:"total"`
	Success int `json:"success"`
	Pending int `json:"pending"`
	Failure int `json:"failure"`
	Skipped int `json:"skipped"`
	Unknown int `json:"unknown"`
}

type Feedback struct {
	Comments          int            `json:"comments"`
	Reviews           int            `json:"reviews"`
	Approvals         int            `json:"approvals"`
	ChangesRequested  int            `json:"changes_requested"`
	UnresolvedThreads int            `json:"unresolved_threads"`
	Threads           []ReviewThread `json:"threads"`
	ThreadsTruncated  bool           `json:"threads_truncated"`
}

type ReviewThread struct {
	ID                string          `json:"id"`
	Path              string          `json:"path"`
	Line              *int            `json:"line,omitempty"`
	OriginalLine      *int            `json:"original_line,omitempty"`
	Outdated          bool            `json:"outdated"`
	Comments          []ReviewComment `json:"comments"`
	CommentsTruncated bool            `json:"comments_truncated"`
}

type ReviewComment struct {
	ID            string    `json:"id"`
	Author        string    `json:"author"`
	Body          string    `json:"body"`
	BodyTruncated bool      `json:"body_truncated"`
	URL           string    `json:"url"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type Issue struct {
	Number        int       `json:"number"`
	Title         string    `json:"title"`
	Body          string    `json:"body"`
	BodyTruncated bool      `json:"body_truncated"`
	URL           string    `json:"url"`
	State         string    `json:"state"`
	Labels        []string  `json:"labels"`
	Assignees     []string  `json:"assignees"`
	UpdatedAt     time.Time `json:"updated_at"`
	ClosedAt      time.Time `json:"closed_at,omitzero"`
}

type Worktree struct {
	Path       string    `json:"path"`
	HeadOID    string    `json:"head_oid"`
	Upstream   string    `json:"upstream,omitempty"`
	Staged     int       `json:"staged"`
	Unstaged   int       `json:"unstaged"`
	Untracked  int       `json:"untracked"`
	Conflicted int       `json:"conflicted"`
	Ahead      int       `json:"ahead"`
	Behind     int       `json:"behind"`
	AheadBase  int       `json:"ahead_base"`
	BehindBase int       `json:"behind_base"`
	Detached   bool      `json:"detached"`
	Locked     bool      `json:"locked"`
	Prunable   bool      `json:"prunable"`
	UpdatedAt  time.Time `json:"updated_at"`
	StatusHash string    `json:"-"`
}

type PullRequest struct {
	Number         int          `json:"number"`
	Title          string       `json:"title"`
	Body           string       `json:"body"`
	BodyTruncated  bool         `json:"body_truncated"`
	URL            string       `json:"url"`
	HeadRefName    string       `json:"head_ref_name"`
	HeadRefOID     string       `json:"head_ref_oid"`
	BaseRefName    string       `json:"base_ref_name"`
	State          string       `json:"state"`
	IsDraft        bool         `json:"is_draft"`
	UpdatedAt      time.Time    `json:"updated_at"`
	MergedAt       time.Time    `json:"merged_at,omitzero"`
	ClosedAt       time.Time    `json:"closed_at,omitzero"`
	ReviewDecision string       `json:"review_decision,omitempty"`
	MergeState     string       `json:"merge_state_status,omitempty"`
	Mergeable      string       `json:"mergeable,omitempty"`
	CI             CIState      `json:"ci_state"`
	Checks         CheckSummary `json:"checks"`
	Feedback       Feedback     `json:"feedback"`
	ClosingIssues  []Issue      `json:"closing_issues"`
}

type ScanError struct {
	Repository     string `json:"repository,omitempty"`
	RepositoryPath string `json:"repository_path,omitempty"`
	Stage          string `json:"stage"`
	Message        string `json:"message"`
	Code           string `json:"code,omitempty"`
	WorktreePath   string `json:"worktree_path,omitempty"`
}

type Refresh struct {
	Repository string    `json:"repository"`
	Attempted  bool      `json:"attempted"`
	Refreshed  bool      `json:"refreshed"`
	At         time.Time `json:"at,omitempty"`
	Error      string    `json:"error,omitempty"`
}
