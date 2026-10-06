package model

import "time"

// DeployStatus records which deploy pipelines on the default branch are
// behind their merged pull requests. A pipeline is behind when an automatic
// attempt after its last success failed, was cancelled, or was skipped, and
// pull requests merged after that success are not yet deployed.
type DeployStatus struct {
	Fingerprint  string                  `json:"fingerprint,omitempty"`
	CheckedAt    time.Time               `json:"checked_at"`
	Message      string                  `json:"message,omitempty"`
	Pipelines    []DeployGap             `json:"pipelines,omitempty"`
	PullRequests []UndeployedPullRequest `json:"pull_requests,omitempty"`
}

// DeployGap is one deploy pipeline whose newest attempt did not deploy.
type DeployGap struct {
	File          string     `json:"file"`
	Name          string     `json:"name"`
	Conclusion    string     `json:"conclusion"`
	URL           string     `json:"url,omitempty"`
	AttemptAt     time.Time  `json:"attempt_at"`
	LastSuccessAt *time.Time `json:"last_success_at,omitempty"`
}

// UndeployedPullRequest is a pull request merged into the default branch
// after the oldest last-successful deploy among behind pipelines.
type UndeployedPullRequest struct {
	Number      int       `json:"number"`
	Title       string    `json:"title"`
	URL         string    `json:"url,omitempty"`
	HeadRefName string    `json:"head_ref_name,omitempty"`
	Author      string    `json:"author,omitempty"`
	MergedAt    time.Time `json:"merged_at"`
}

// IsBehind reports whether any deploy pipeline is behind.
func (s *DeployStatus) IsBehind() bool {
	return s != nil && len(s.Pipelines) > 0
}
