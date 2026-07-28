package workscan

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/memoryscan"
	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/threadstate"
)

func TestScannerGoldenR2EventSinkThreads(t *testing.T) {
	now := time.Date(2026, 7, 28, 14, 0, 0, 0, time.UTC)
	r2 := config.Repository{Name: "r2", Path: "/repo/r2", GitHub: "owner/r2", Base: "main", Remote: "origin"}
	eventSink := config.Repository{Name: "event-sink", Path: "/repo/event-sink", GitHub: "owner/event-sink", Base: "main", Remote: "origin"}
	github := fakeGitHub{results: map[string]model.RemoteEvidence{
		r2.GitHub: evidence(
			[]model.PullRequest{openPR("r2", 11, "R2 implementation", "GH-10", issue("r2", 10, "R2 storage", "OPEN", now), now)},
			[]model.Issue{issue("r2", 10, "R2 storage", "OPEN", now)},
		),
		eventSink.GitHub: evidence(
			[]model.PullRequest{openPR("event-sink", 21, "Event sink implementation", "GH-20", issue("event-sink", 20, "Event sink", "OPEN", now), now)},
			[]model.Issue{issue("event-sink", 20, "Event sink", "OPEN", now)},
		),
	}}
	memory := fakeMemory{results: map[string]memoryscan.Result{
		r2.Path: {Documents: []memoryscan.Document{{
			ID: "spec:0001", FeatureID: "0001", Slug: "r2-storage", Title: "R2 storage",
			Phase: "implement", Path: "docs/specs/0001-r2/SPEC.md", Selected: true,
			Purpose: "Store durable payloads in R2.", Context: "Production deployment changes object storage ownership.",
			IssueURLs: []string{"https://github.com/owner/r2/issues/10"}, UpdatedAt: now,
			Obligations:  []memoryscan.Candidate{{Summary: "Provision and deploy the production R2 bucket.", Category: "operational"}},
			Implications: []memoryscan.Candidate{{Summary: "Production object storage ownership changes.", Category: "material"}},
		}}},
		eventSink.Path: {Documents: []memoryscan.Document{{
			ID: "spec:0002", FeatureID: "0002", Slug: "event-sink", Title: "Event sink",
			Phase: "implement", Path: "docs/specs/0002-event-sink/SPEC.md", Selected: true,
			Purpose: "Persist application events.", Context: "Deployment requires the event sink infrastructure.",
			IssueURLs: []string{"https://github.com/owner/event-sink/issues/20"}, UpdatedAt: now,
			References: []memoryscan.Reference{{
				ID: "r2", Type: "github_issue", Target: "https://github.com/owner/r2/issues/10",
				Relation: "depends_on",
			}},
			Obligations:  []memoryscan.Candidate{{Summary: "Deploy the event sink infrastructure.", Category: "operational"}},
			Implications: []memoryscan.Candidate{{Summary: "Production event routing changes.", Category: "material"}},
		}}},
	}}
	scanner := testScanner(now, []config.Repository{r2, eventSink}, github, memory, &fakeStore{state: threadstate.Empty()})

	result, err := scanner.Scan(context.Background(), testConfig(), false, false)
	if err != nil {
		t.Fatal(err)
	}
	if result.SchemaVersion != model.ThreadScanSchemaVersion || result.Summary.Threads != 2 {
		t.Fatalf("result summary = %#v", result.Summary)
	}
	r2Thread := threadByID(t, result.Threads, "issue:owner/r2#10")
	eventThread := threadByID(t, result.Threads, "issue:owner/event-sink#20")
	if r2Thread.Phase != model.ThreadReviewing || eventThread.Phase != model.ThreadReviewing {
		t.Fatalf("phases = %s, %s", r2Thread.Phase, eventThread.Phase)
	}
	if len(r2Thread.Obligations) != 1 || len(eventThread.Obligations) != 1 {
		t.Fatalf("obligations = %#v / %#v", r2Thread.Obligations, eventThread.Obligations)
	}
	if len(eventThread.Dependencies) != 1 ||
		eventThread.Dependencies[0].TargetThreadID != r2Thread.ID ||
		eventThread.Dependencies[0].Basis != model.BasisExplicit {
		t.Fatalf("event-sink dependency = %#v", eventThread.Dependencies)
	}
	if result.Summary.Attention != 2 {
		t.Fatalf("boundary attention = %d, want 2", result.Summary.Attention)
	}
}

func TestScannerRemoteFailurePreservesCachedOpenPRAsStale(t *testing.T) {
	now := time.Date(2026, 7, 28, 14, 0, 0, 0, time.UTC)
	repository := config.Repository{Name: "r2", Path: "/repo/r2", GitHub: "owner/r2", Base: "main", Remote: "origin"}
	cached := evidence([]model.PullRequest{openPR("r2", 11, "R2 implementation", "GH-10", issue("r2", 10, "R2", "OPEN", now), now)}, nil)
	state := threadstate.Empty()
	state.Remote[repository.GitHub] = threadstate.RemoteCache{ObservedAt: now.Add(-2 * time.Hour), Evidence: cached}
	github := fakeGitHub{results: map[string]model.RemoteEvidence{
		repository.GitHub: {Errors: []model.ScanError{{Repository: "r2", Stage: "github-prs", Message: "offline"}}},
	}}
	scanner := testScanner(now, []config.Repository{repository}, github, fakeMemory{}, &fakeStore{state: state})

	result, err := scanner.Scan(context.Background(), testConfig(), false, false)
	if err != nil {
		t.Fatal(err)
	}
	thread := threadByID(t, result.Threads, "issue:owner/r2#10")
	if len(thread.Artifacts) != 1 || thread.Artifacts[0].State != "open" ||
		thread.Artifacts[0].Freshness != "stale" {
		t.Fatalf("cached artifact = %#v", thread.Artifacts)
	}
	if result.Summary.Attention != 1 || thread.Attention[0].Kind != model.AttentionUncertain {
		t.Fatalf("stale attention = %#v", thread.Attention)
	}
	if len(result.Errors) != 1 || result.Errors[0].Message != "offline" {
		t.Fatalf("errors = %#v", result.Errors)
	}
}

func TestScannerLocalUsesCacheWithoutCallingGitHub(t *testing.T) {
	now := time.Date(2026, 7, 28, 14, 0, 0, 0, time.UTC)
	repository := config.Repository{Name: "local", Path: "/repo/local", GitHub: "owner/local", Base: "main", Remote: "origin"}
	github := &countingGitHub{}
	scanner := testScanner(now, []config.Repository{repository}, github, fakeMemory{}, &fakeStore{state: threadstate.Empty()})
	scanner.Git = fakeGit{results: map[string]gitscan.Result{
		repository.GitHub: {Lanes: []gitscan.LocalLane{localLane("GH-1", model.PublicationNoUpstream, model.Worktree{
			Path: "/repo/local", AheadBase: 1, UpdatedAt: now,
		})}},
	}}

	result, err := scanner.ScanLocal(context.Background(), testConfig(), false)
	if err != nil {
		t.Fatal(err)
	}
	if github.calls != 0 || len(result.Threads) != 1 || result.Threads[0].Phase != model.ThreadImplementing {
		t.Fatalf("calls = %d, result = %#v", github.calls, result)
	}
}

func TestScannerReturnsEmptySelectedBoundary(t *testing.T) {
	store := &fakeStore{state: threadstate.Empty()}
	scanner := testScanner(time.Now(), nil, fakeGitHub{}, fakeMemory{}, store)
	result, err := scanner.Scan(context.Background(), testConfig(), false, false)
	if err != nil {
		t.Fatal(err)
	}
	if result.Summary.Projects != 0 || len(result.Threads) != 0 {
		t.Fatalf("result = %#v", result)
	}
}

func TestBoundedRemoteHistoryDoesNotReplayHistoryButKeepsObservedFinalState(t *testing.T) {
	now := time.Now().UTC()
	open := openPR("r2", 11, "Open", "GH-10", issue("r2", 10, "R2", "OPEN", now), now)
	merged := open
	merged.State = "MERGED"
	merged.MergedAt = now
	historical := openPR("r2", 12, "Historical", "GH-12", issue("r2", 12, "Old", "CLOSED", now), now)
	historical.State = "MERGED"
	historical.MergedAt = now
	current := evidence([]model.PullRequest{merged, historical}, []model.Issue{
		issue("r2", 10, "R2", "CLOSED", now),
		issue("r2", 12, "Old", "CLOSED", now),
	})
	previous := threadstate.RemoteCache{ObservedAt: now.Add(-time.Hour), Evidence: evidence(
		[]model.PullRequest{open}, []model.Issue{issue("r2", 10, "R2", "OPEN", now.Add(-time.Hour))},
	)}
	filtered := boundedRemoteHistory(current, previous, true, nil, nil)
	if len(filtered.PullRequests) != 1 || filtered.PullRequests[0].Number != 11 ||
		len(filtered.Issues) != 1 || filtered.Issues[0].Number != 10 {
		t.Fatalf("filtered evidence = %#v", filtered)
	}
}

func TestBoundedRemoteHistoryKeepsFinalStateForLocalIssueLane(t *testing.T) {
	now := time.Now().UTC()
	current := evidence(nil, []model.Issue{
		issue("flowcore", 38, "Weekly maintenance", "CLOSED", now),
	})
	locals := []gitscan.LocalLane{localLane(
		"GH-38", model.PublicationPublished,
		model.Worktree{Path: "/private/tmp/flowcore", UpdatedAt: now},
	)}
	filtered := boundedRemoteHistory(current, threadstate.RemoteCache{}, false, locals, nil)
	if len(filtered.Issues) != 1 || filtered.Issues[0].Number != 38 {
		t.Fatalf("closed local issue state was discarded: %#v", filtered)
	}
}

func TestInferFallsBackToDeterministicThreadsOnModelFailure(t *testing.T) {
	now := time.Date(2026, 7, 28, 14, 0, 0, 0, time.UTC)
	repository := config.Repository{Name: "r2", Path: "/repo/r2", GitHub: "owner/r2", Base: "main"}
	memory := fakeMemory{results: map[string]memoryscan.Result{
		repository.Path: {Documents: []memoryscan.Document{{
			ID: "spec:0001", FeatureID: "0001", Title: "R2", Phase: "implement",
			Selected: true, Path: "docs/specs/0001-r2/SPEC.md", Purpose: "Store payloads.",
			UpdatedAt: now,
		}}},
	}}
	scanner := testScanner(now, []config.Repository{repository}, fakeGitHub{}, memory, &fakeStore{state: threadstate.Empty()})
	scanner.Inference = failingInference{err: errors.New("ollama unavailable")}
	cfg := testConfig()
	cfg.Settings.OllamaModel = "local-model"
	result, err := scanner.Infer(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Threads) != 1 || result.Threads[0].Goal != "Store payloads." ||
		result.Threads[0].InferenceStatus != "unavailable" {
		t.Fatalf("fallback result = %#v", result)
	}
	if len(result.Warnings) != 1 || result.Warnings[0].Stage != "local-inference" {
		t.Fatalf("warnings = %#v", result.Warnings)
	}
}

func TestInferUsesExistingScanWithDefaultClock(t *testing.T) {
	now := time.Now().UTC()
	repository := config.Repository{Name: "r2", Path: "/repo/r2", GitHub: "owner/r2", Base: "main"}
	memory := &countingMemory{result: memoryscan.Result{Documents: []memoryscan.Document{{
		ID: "spec:0001", FeatureID: "0001", Title: "R2", Phase: "implement",
		Selected: true, Path: "docs/specs/0001-r2/SPEC.md", Purpose: "Store payloads.",
		UpdatedAt: now,
	}}}}
	scanner := testScanner(now, []config.Repository{repository}, fakeGitHub{}, memory, &fakeStore{state: threadstate.Empty()})
	scanner.Now = nil
	scanner.Inference = successfulInference{}
	cfg := testConfig()
	cfg.Settings.OllamaModel = "local-model"

	result, err := scanner.Infer(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	if memory.calls != 1 ||
		result.Summary.Threads != 1 ||
		result.Summary.InFlight != 1 ||
		result.Threads[0].InferenceStatus != "current" {
		t.Fatalf("calls=%d result=%#v", memory.calls, result)
	}
}
