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
	IsDraft                 bool      `json:"is_draft"`
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

type ProjectPullRequestScan struct {
	SchemaVersion          int                   `json:"schema_version"`
	GeneratedAt            time.Time             `json:"generated_at"`
	CheckedAt              *time.Time            `json:"checked_at,omitempty"`
	ObservedAt             *time.Time            `json:"observed_at,omitempty"`
	RefreshIntervalSeconds int64                 `json:"refresh_interval_seconds"`
	Projects               []ProjectPullRequests `json:"projects"`
	Errors                 []ScanError           `json:"errors"`
	Warnings               []ScanError           `json:"warnings"`
}
