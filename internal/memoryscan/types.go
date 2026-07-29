package memoryscan

import "time"

type Reference struct {
	ID       string
	Type     string
	Target   string
	Relation string
}

type Candidate struct {
	Summary   string
	Satisfied bool
	Category  string
}

type Document struct {
	ID              string
	FeatureID       string
	Slug            string
	WorkflowVersion int
	Title           string
	Phase           string
	Selected        bool
	RepositoryRoot  string
	Path            string
	Purpose         string
	Context         string
	Plan            string
	Decisions       string
	Outcome         string
	References      []Reference
	IssueURLs       []string
	IssueNumbers    []int
	Obligations     []Candidate
	Implications    []Candidate
	UpdatedAt       time.Time
}

type Diagnostic struct {
	Path    string
	Message string
}

type Result struct {
	Documents   []Document
	Diagnostics []Diagnostic
}
