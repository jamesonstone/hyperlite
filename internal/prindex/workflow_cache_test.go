package prindex

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestStoreRoundTripsWorkflowActivityAndPollState(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	store := Store{Path: filepath.Join(t.TempDir(), "cache.json"), Now: func() time.Time { return now }}
	observed := now.Add(-time.Minute)
	_, err := store.Update(func(state *cacheState) bool {
		state.Repositories["owner/one"] = cacheEntry{
			Repository: "owner/one", ObservedAt: observed,
			Workflows: &model.ProjectWorkflowActivity{
				Catalog: []model.WorkflowDefinition{{File: "ci.yaml", Name: "ci"}},
				Runs: []model.WorkflowRun{
					{File: "ci.yaml", Scope: model.WorkflowRunScopeTip, Status: "COMPLETED", CreatedAt: observed},
					{File: "deploy.yaml", Scope: model.WorkflowRunScopeTip, Status: "IN_PROGRESS", CreatedAt: now},
				},
				TreeOID: "tree-1", ObservedAt: &observed,
			},
		}
		state.Activity = &cachedActivityState{LastCheckedAt: observed, BurstStartedAt: observed, WindowResetAt: now, PollsThisWindow: 3}
		return true
	})
	if err != nil {
		t.Fatal(err)
	}
	loaded, warning, err := store.Load()
	if err != nil || warning != "" {
		t.Fatalf("load: %v %q", err, warning)
	}
	entry := loaded.Repositories["owner/one"]
	if entry.Workflows == nil || entry.Workflows.TreeOID != "tree-1" || len(entry.Workflows.Catalog) != 1 ||
		len(entry.Workflows.Runs) != 2 || entry.Workflows.Runs[0].File != "deploy.yaml" ||
		entry.Workflows.Deployments == nil || entry.Workflows.ObservedAt == nil {
		t.Fatalf("workflows = %#v", entry.Workflows)
	}
	if loaded.Activity == nil || loaded.Activity.PollsThisWindow != 3 || !loaded.Activity.WindowResetAt.Equal(now) {
		t.Fatalf("activity = %#v", loaded.Activity)
	}
	if activityWindowPolls(loaded.Activity, now) != 3 || activityWindowPolls(loaded.Activity, now.Add(time.Hour)) != 0 {
		t.Fatalf("window polls = %d / %d", activityWindowPolls(loaded.Activity, now), activityWindowPolls(loaded.Activity, now.Add(time.Hour)))
	}
}

func TestStoreLoadsLegacyCacheWithoutWorkflowFields(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cache.json")
	legacy := `{"version":1,"projects":{},"repositories":{"owner/one":{"repository":"owner/one","observed_at":"2026-09-12T19:00:00Z","pull_requests":[]}},"updated_at":"2026-09-12T19:00:00Z"}` + "\n"
	if err := os.WriteFile(path, []byte(legacy), 0o600); err != nil {
		t.Fatal(err)
	}
	loaded, warning, err := Store{Path: path}.Load()
	if err != nil || warning != "" {
		t.Fatalf("load: %v %q", err, warning)
	}
	entry := loaded.Repositories["owner/one"]
	if entry.Workflows != nil || loaded.Activity != nil || !cacheEntryNeedsWorkflowActivity(entry) {
		t.Fatalf("legacy entry = %#v activity = %#v", entry, loaded.Activity)
	}
}

func TestRecordActivityPollResetsCountOnNewWindow(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	state := &cachedActivityState{WindowResetAt: now.Add(-time.Hour), PollsThisWindow: 40}
	recordActivityPoll(state, now.Add(30*time.Minute), now)
	if state.PollsThisWindow != 1 || !state.WindowResetAt.Equal(now.Add(30*time.Minute)) || !state.LastCheckedAt.Equal(now) {
		t.Fatalf("state = %#v", state)
	}
	recordActivityPoll(state, now.Add(30*time.Minute), now.Add(time.Minute))
	if state.PollsThisWindow != 2 {
		t.Fatalf("state = %#v", state)
	}
}
