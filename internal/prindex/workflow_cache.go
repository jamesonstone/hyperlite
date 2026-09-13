package prindex

import (
	"sort"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

// cachedActivityState tracks automatic activity polling across helper
// processes so the quota governor sees one shared history.
type cachedActivityState struct {
	LastCheckedAt   time.Time `json:"last_checked_at,omitempty"`
	BurstStartedAt  time.Time `json:"burst_started_at,omitempty"`
	WindowResetAt   time.Time `json:"window_reset_at,omitempty"`
	PollsThisWindow int       `json:"polls_this_window,omitempty"`
}

// activityWindowPolls returns the poll count for the current quota window,
// treating a changed reset time as a fresh window.
func activityWindowPolls(state *cachedActivityState, resetAt time.Time) int {
	if state == nil || resetAt.IsZero() || !state.WindowResetAt.Equal(resetAt) {
		return 0
	}
	return state.PollsThisWindow
}

func recordActivityPoll(state *cachedActivityState, resetAt, now time.Time) {
	if !resetAt.IsZero() && !state.WindowResetAt.Equal(resetAt) {
		state.WindowResetAt = resetAt.UTC()
		state.PollsThisWindow = 0
	}
	state.PollsThisWindow++
	state.LastCheckedAt = now.UTC()
}

func normalizeWorkflowActivity(activity *model.ProjectWorkflowActivity) {
	if activity == nil {
		return
	}
	if activity.Catalog == nil {
		activity.Catalog = []model.WorkflowDefinition{}
	}
	if activity.Runs == nil {
		activity.Runs = []model.WorkflowRun{}
	}
	if activity.Deployments == nil {
		activity.Deployments = []model.Deployment{}
	}
}

func sortWorkflowActivity(activity *model.ProjectWorkflowActivity) {
	if activity == nil {
		return
	}
	sort.SliceStable(activity.Runs, func(i, j int) bool {
		if !activity.Runs[i].CreatedAt.Equal(activity.Runs[j].CreatedAt) {
			return activity.Runs[i].CreatedAt.After(activity.Runs[j].CreatedAt)
		}
		return activity.Runs[i].File < activity.Runs[j].File
	})
	sort.SliceStable(activity.Deployments, func(i, j int) bool {
		return activity.Deployments[i].CreatedAt.After(activity.Deployments[j].CreatedAt)
	})
}

func cloneWorkflowActivity(activity *model.ProjectWorkflowActivity) *model.ProjectWorkflowActivity {
	if activity == nil {
		return nil
	}
	cloned := *activity
	cloned.Catalog = append([]model.WorkflowDefinition(nil), activity.Catalog...)
	cloned.Runs = append([]model.WorkflowRun(nil), activity.Runs...)
	cloned.Deployments = append([]model.Deployment(nil), activity.Deployments...)
	if activity.CheckedAt != nil {
		checkedAt := *activity.CheckedAt
		cloned.CheckedAt = &checkedAt
	}
	if activity.ObservedAt != nil {
		observedAt := *activity.ObservedAt
		cloned.ObservedAt = &observedAt
	}
	normalizeWorkflowActivity(&cloned)
	return &cloned
}
