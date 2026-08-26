package model

import "time"

const ProjectPullRequestScanSchemaVersion = 1

type ProjectPullRequestStatus string

const (
	ProjectPullRequestsCurrent     ProjectPullRequestStatus = "current"
	ProjectPullRequestsCached      ProjectPullRequestStatus = "cached"
	ProjectPullRequestsUnavailable ProjectPullRequestStatus = "unavailable"
)

type ProjectPullRequest struct {
	ID                      string    `json:"id"`
	Number                  int       `json:"number"`
	Title                   string    `json:"title"`
	URL                     string    `json:"url"`
	HeadRefName             string    `json:"head_ref_name"`
	HeadRefOID              string    `json:"head_ref_oid"`
	IsDraft                 bool      `json:"is_draft"`
	HasMergeConflict        bool      `json:"has_merge_conflict,omitempty"`
	UnresolvedReviewThreads *int      `json:"unresolved_review_threads,omitempty"`
	UpdatedAt               time.Time `json:"updated_at"`
}

type ProjectPullRequests struct {
	ID           string                   `json:"id"`
	Name         string                   `json:"name"`
	Path         string                   `json:"path"`
	Repository   string                   `json:"repository,omitempty"`
	Status       ProjectPullRequestStatus `json:"status"`
	Message      string                   `json:"message,omitempty"`
	CheckedAt    *time.Time               `json:"checked_at,omitempty"`
	ObservedAt   *time.Time               `json:"observed_at,omitempty"`
	PullRequests []ProjectPullRequest     `json:"pull_requests"`
}

type GitHubRateLimit struct {
	Limit      int                      `json:"limit"`
	Used       int                      `json:"used"`
	Remaining  int                      `json:"remaining"`
	ResetAt    time.Time                `json:"reset_at"`
	Cost       int                      `json:"cost"`
	NodeCount  int                      `json:"node_count"`
	ObservedAt time.Time                `json:"observed_at"`
	BurnRate   *GitHubRateLimitBurnRate `json:"burn_rate,omitempty"`
}

type GitHubRateLimitBurnRate struct {
	PointsPerHour         float64    `json:"points_per_hour"`
	SampleSeconds         int64      `json:"sample_seconds"`
	ProjectedExhaustionAt *time.Time `json:"projected_exhaustion_at,omitempty"`
}

type ProjectPullRequestScan struct {
	SchemaVersion          int                   `json:"schema_version"`
	GeneratedAt            time.Time             `json:"generated_at"`
	CheckedAt              *time.Time            `json:"checked_at,omitempty"`
	ObservedAt             *time.Time            `json:"observed_at,omitempty"`
	RateLimit              *GitHubRateLimit      `json:"rate_limit,omitempty"`
	RefreshIntervalSeconds int64                 `json:"refresh_interval_seconds"`
	Projects               []ProjectPullRequests `json:"projects"`
	Errors                 []ScanError           `json:"errors"`
	Warnings               []ScanError           `json:"warnings"`
}
