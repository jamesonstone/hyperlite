package prindex

import (
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

var deployBase = time.Date(2026, 10, 5, 12, 0, 0, 0, time.UTC)

func deployAt(hours int) time.Time { return deployBase.Add(time.Duration(hours) * time.Hour) }

func run(file, event, status, conclusion string, hours int) deployRun {
	return deployRun{
		Path: ".github/workflows/" + file, Name: workflowDisplayName(file), Event: event, Status: status,
		Conclusion: conclusion, URL: "https://example.com/" + file, CreatedAt: deployAt(hours),
		CommitAt: deployAt(hours).Add(-time.Minute),
	}
}

func TestDeployGapsFlagsSkippedAutomaticRunAfterSuccess(t *testing.T) {
	gaps, cutoff := deployGaps([]deployRun{
		run("deploy.yaml", "workflow_run", "completed", "success", -48),
		run("deploy.yaml", "workflow_run", "completed", "skipped", 0),
		run("ci.yaml", "push", "completed", "failure", 0),
	})
	if len(gaps) != 1 || gaps[0].File != "deploy.yaml" || gaps[0].Conclusion != "SKIPPED" {
		t.Fatalf("skipped automatic deploy after success should be behind: %#v", gaps)
	}
	success := deployAt(-48).Add(-time.Minute)
	if want := success.Add(mergeCommitSlack); !cutoff.Equal(want) || !gaps[0].LastSuccessAt.Equal(success) {
		t.Fatalf("cutoff = %v, want last success commit %v", cutoff, want)
	}
}

func TestDeployGapsIgnoresGreenRunningAndConditionalPipelines(t *testing.T) {
	cases := map[string][]deployRun{
		"newest success": {
			run("deploy.yaml", "workflow_run", "completed", "success", 0),
			run("deploy.yaml", "workflow_run", "completed", "failure", -1),
		},
		"deploying now": {
			run("deploy.yaml", "workflow_dispatch", "in_progress", "", 0),
			run("deploy.yaml", "workflow_run", "completed", "failure", -1),
		},
		"always skipped": {
			run("mint-production.yaml", "push", "completed", "skipped", 0),
			run("mint-production.yaml", "push", "completed", "skipped", -1),
		},
		"pull request run": {
			run("deploy.yaml", "pull_request", "completed", "failure", 0),
		},
		"manual skip only": {
			run("deploy.yaml", "workflow_dispatch", "completed", "skipped", 0),
			run("deploy.yaml", "workflow_dispatch", "completed", "success", -1),
		},
	}
	for name, runs := range cases {
		if gaps, _ := deployGaps(runs); len(gaps) != 0 {
			t.Fatalf("%s: want no gap, got %#v", name, gaps)
		}
	}
}

func TestDeployGapsWithoutSuccessUsesOldestFailure(t *testing.T) {
	gaps, cutoff := deployGaps([]deployRun{
		run("deploy.yaml", "push", "completed", "cancelled", 0),
		run("deploy.yaml", "push", "completed", "failure", -3),
		run("deploy.yaml", "push", "completed", "skipped", -5),
	})
	if len(gaps) != 1 || gaps[0].Conclusion != "CANCELLED" || gaps[0].LastSuccessAt != nil {
		t.Fatalf("failures without success should be behind: %#v", gaps)
	}
	if want := deployAt(-3).Add(-time.Minute - time.Second); !cutoff.Equal(want) {
		t.Fatalf("cutoff = %v, want just before oldest failure commit %v", cutoff, want)
	}
}

func TestDeployGapsUsesOldestCutoffAcrossPipelines(t *testing.T) {
	_, cutoff := deployGaps([]deployRun{
		run("deploy.yaml", "workflow_run", "completed", "failure", 0),
		run("deploy-nonprod.yaml", "workflow_run", "completed", "failure", 0),
		run("deploy.yaml", "workflow_run", "completed", "success", -10),
		run("deploy-nonprod.yaml", "workflow_run", "completed", "success", -20),
	})
	if want := deployAt(-20).Add(-time.Minute + mergeCommitSlack); !cutoff.Equal(want) {
		t.Fatalf("cutoff = %v, want oldest last success %v", cutoff, want)
	}
}

func TestUndeployedPullRequestsKeepsMergesAfterCutoff(t *testing.T) {
	merged := func(number, hours int) mergedPullRequest {
		at := deployAt(hours)
		return mergedPullRequest{Number: number, Title: " t ", MergedAt: &at}
	}
	pulls := []mergedPullRequest{merged(1, -30), merged(2, -1), {Number: 3}, merged(4, -2)}
	got := undeployedPullRequests(pulls, deployAt(-24))
	if len(got) != 2 || got[0].Number != 2 || got[1].Number != 4 || got[0].Title != "t" {
		t.Fatalf("want merged-after-cutoff newest first, got %#v", got)
	}
	if got := undeployedPullRequests(pulls, time.Time{}); got != nil {
		t.Fatalf("zero cutoff must keep none, got %#v", got)
	}
}

func TestKeepReportableGapsDropsSkipOnlyWithoutMerges(t *testing.T) {
	gaps := []model.DeployGap{{File: "a", Conclusion: "SKIPPED"}, {File: "b", Conclusion: "FAILURE"}}
	if got := keepReportableGaps(gaps, nil); len(got) != 1 || got[0].File != "b" {
		t.Fatalf("skip-only gap without merges should drop: %#v", got)
	}
	if got := keepReportableGaps(gaps, []model.UndeployedPullRequest{{Number: 1}}); len(got) != 2 {
		t.Fatalf("gaps with merges should stay: %#v", got)
	}
}

func TestNeedsDeployCheck(t *testing.T) {
	now := deployBase
	fresh := &model.DeployStatus{Fingerprint: "a", CheckedAt: now.Add(-time.Minute)}
	behind := &model.DeployStatus{Fingerprint: "a", CheckedAt: now.Add(-21 * time.Minute), Pipelines: []model.DeployGap{{}}}
	failed := &model.DeployStatus{Fingerprint: "b", CheckedAt: now.Add(-time.Minute), Message: "boom"}
	cases := []struct {
		name   string
		status *model.DeployStatus
		print  string
		want   bool
	}{
		{"never checked", nil, "a", true},
		{"unchanged", fresh, "a", false},
		{"tip moved", fresh, "b", true},
		{"behind recheck", behind, "a", true},
		{"error backoff", failed, "c", false},
	}
	for _, test := range cases {
		if got := needsDeployCheck(test.status, test.print, now); got != test.want {
			t.Fatalf("%s: needsDeployCheck = %v, want %v", test.name, got, test.want)
		}
	}
}

func TestStaleRunsPageRejectsLaggingListings(t *testing.T) {
	short := rawDeployRuns{TotalCount: 204, WorkflowRuns: make([]rawDeployRun, 40)}
	if staleRunsPage(short, 1, nil, time.Time{}) == nil {
		t.Fatal("a short page while total_count reports more runs must be stale")
	}
	complete := rawDeployRuns{TotalCount: 40, WorkflowRuns: short.WorkflowRuns}
	old := []deployRun{{CreatedAt: deployAt(-2400)}}
	if staleRunsPage(complete, 1, old, deployAt(0)) == nil {
		t.Fatal("a first page older than the observed tip run must be stale")
	}
	if err := staleRunsPage(complete, 1, []deployRun{{CreatedAt: deployAt(0).Add(-time.Minute)}}, deployAt(0)); err != nil {
		t.Fatalf("a current page within slack is fine: %v", err)
	}
}
