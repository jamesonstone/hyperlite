package model

type RemoteEvidence struct {
	PullRequests []PullRequest `json:"pull_requests"`
	Issues       []Issue       `json:"issues"`
	Errors       []ScanError   `json:"errors"`
	Warnings     []ScanError   `json:"warnings"`
}

type RemoteCollection struct {
	Repositories map[string]RemoteEvidence `json:"repositories"`
	Errors       []ScanError               `json:"errors"`
	Warnings     []ScanError               `json:"warnings"`
}
