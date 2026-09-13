package model

import (
	"strings"
	"time"
)

// WorkflowDefinition is one workflow file on the repository default branch.
// File is the join key between the catalog and observed runs because GitHub's
// WorkflowRun.workflow.resourcePath ends with the same file name.
type WorkflowDefinition struct {
	File string `json:"file"`
	Name string `json:"name"`
	URL  string `json:"url,omitempty"`
}

type WorkflowRun struct {
	File              string    `json:"file"`
	Name              string    `json:"name"`
	Scope             string    `json:"scope"`
	PullRequestNumber int       `json:"pull_request_number,omitempty"`
	HeadRefName       string    `json:"head_ref_name,omitempty"`
	HeadOID           string    `json:"head_oid,omitempty"`
	Status            string    `json:"status"`
	Conclusion        string    `json:"conclusion,omitempty"`
	Event             string    `json:"event,omitempty"`
	RunNumber         int       `json:"run_number,omitempty"`
	DisplayTitle      string    `json:"display_title,omitempty"`
	URL               string    `json:"url,omitempty"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

const (
	WorkflowRunScopeTip         = "tip"
	WorkflowRunScopePullRequest = "pull_request"
)

type Deployment struct {
	Environment string    `json:"environment"`
	State       string    `json:"state"`
	Ref         string    `json:"ref,omitempty"`
	CommitOID   string    `json:"commit_oid,omitempty"`
	LogURL      string    `json:"log_url,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// ProjectWorkflowActivity is the per-repository Actions projection. CheckedAt
// is the last attempt and ObservedAt the last success, mirroring pull-request
// freshness so a failed poll cannot present stale runs as current.
type ProjectWorkflowActivity struct {
	Catalog     []WorkflowDefinition `json:"catalog"`
	Runs        []WorkflowRun        `json:"runs"`
	Deployments []Deployment         `json:"deployments"`
	TreeOID     string               `json:"tree_oid,omitempty"`
	CheckedAt   *time.Time           `json:"checked_at,omitempty"`
	ObservedAt  *time.Time           `json:"observed_at,omitempty"`
	Message     string               `json:"message,omitempty"`
}

// ActivityPollDecision reports whether an automatic activity poll may run so
// the native app never guesses at quota policy.
type ActivityPollDecision struct {
	Allowed         bool       `json:"allowed"`
	Reason          string     `json:"reason"`
	NextEligibleAt  *time.Time `json:"next_eligible_at,omitempty"`
	ActiveRunCount  int        `json:"active_run_count"`
	IntervalSeconds int64      `json:"interval_seconds"`
	MaxBurstSeconds int64      `json:"max_burst_seconds"`
	BurstStartedAt  *time.Time `json:"burst_started_at,omitempty"`
	LastCheckedAt   *time.Time `json:"last_checked_at,omitempty"`
	PollsThisWindow int        `json:"polls_this_window"`
}

func (r WorkflowRun) IsActive() bool {
	switch strings.ToUpper(strings.TrimSpace(r.Status)) {
	case "QUEUED", "IN_PROGRESS", "WAITING", "PENDING", "REQUESTED":
		return true
	}
	return false
}

func (d Deployment) IsActive() bool {
	switch strings.ToUpper(strings.TrimSpace(d.State)) {
	case "PENDING", "QUEUED", "IN_PROGRESS", "WAITING":
		return true
	}
	return false
}

func (a ProjectWorkflowActivity) ActiveRunCount() int {
	count := 0
	for _, run := range a.Runs {
		if run.IsActive() {
			count++
		}
	}
	for _, deployment := range a.Deployments {
		if deployment.IsActive() {
			count++
		}
	}
	return count
}

// ActivePullRequestNumbers lists the pull requests whose head has an active
// run so a follow-up poll can refresh only those heads.
func (a ProjectWorkflowActivity) ActivePullRequestNumbers() []int {
	seen := map[int]struct{}{}
	var numbers []int
	for _, run := range a.Runs {
		if !run.IsActive() || run.PullRequestNumber <= 0 {
			continue
		}
		if _, duplicate := seen[run.PullRequestNumber]; duplicate {
			continue
		}
		seen[run.PullRequestNumber] = struct{}{}
		numbers = append(numbers, run.PullRequestNumber)
	}
	return numbers
}
