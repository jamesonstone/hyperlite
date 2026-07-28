package workscan

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
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
			[]model.PullRequest{openPR(11, "R2 implementation", "GH-10", issue(10, "R2 storage", "OPEN", now), now)},
			[]model.Issue{issue(10, "R2 storage", "OPEN", now)},
		),
		eventSink.GitHub: evidence(
			[]model.PullRequest{openPR(21, "Event sink implementation", "GH-20", issue(20, "Event sink", "OPEN", now), now)},
			[]model.Issue{issue(20, "Event sink", "OPEN", now)},
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
	cached := evidence([]model.PullRequest{openPR(11, "R2 implementation", "GH-10", issue(10, "R2", "OPEN", now), now)}, nil)
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
	open := openPR(11, "Open", "GH-10", issue(10, "R2", "OPEN", now), now)
	merged := open
	merged.State = "MERGED"
	merged.MergedAt = now
	historical := openPR(12, "Historical", "GH-12", issue(12, "Old", "CLOSED", now), now)
	historical.State = "MERGED"
	historical.MergedAt = now
	current := evidence([]model.PullRequest{merged, historical}, []model.Issue{
		issue(10, "R2", "CLOSED", now),
		issue(12, "Old", "CLOSED", now),
	})
	previous := threadstate.RemoteCache{ObservedAt: now.Add(-time.Hour), Evidence: evidence(
		[]model.PullRequest{open}, []model.Issue{issue(10, "R2", "OPEN", now.Add(-time.Hour))},
	)}
	filtered := boundedRemoteHistory(current, previous, true, nil, nil)
	if len(filtered.PullRequests) != 1 || filtered.PullRequests[0].Number != 11 ||
		len(filtered.Issues) != 1 || filtered.Issues[0].Number != 10 {
		t.Fatalf("filtered evidence = %#v", filtered)
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

func testScanner(
	now time.Time,
	repositories []config.Repository,
	github GitHubClient,
	memory MemoryLoader,
	store StateStore,
) Scanner {
	return Scanner{
		Git: fakeGit{}, GitHub: github,
		Discovery: fakeDiscoverer{result: discovery.Result{Repositories: repositories}},
		Memory:    memory, Store: store, Now: func() time.Time { return now },
	}
}

func testConfig() config.Config {
	return config.Config{
		Version: config.Version,
		Settings: config.Settings{
			MaxParallel: 4, GitHubAuthor: "@me", GitHubScope: config.GitHubScopeMine,
			RemoteRefreshInterval: time.Hour, StaleAfter: time.Hour,
		},
		Sources: []config.Source{{Path: "/source"}},
	}
}

func evidence(pullRequests []model.PullRequest, issues []model.Issue) model.RemoteEvidence {
	return model.RemoteEvidence{
		PullRequests: pullRequests, Issues: issues,
		Errors: []model.ScanError{}, Warnings: []model.ScanError{},
	}
}

func issue(number int, title, state string, now time.Time) model.Issue {
	return model.Issue{
		Number: number, Title: title, Body: "Goal body", State: state,
		URL:       "https://github.com/owner/" + repositoryForIssue(number) + "/issues/" + strconv.Itoa(number),
		UpdatedAt: now,
	}
}

func repositoryForIssue(number int) string {
	if number == 20 {
		return "event-sink"
	}
	return "r2"
}

func openPR(number int, title, branch string, closing model.Issue, now time.Time) model.PullRequest {
	repository := repositoryForIssue(closing.Number)
	return model.PullRequest{
		Number: number, Title: title, Body: "Substantial implementation",
		URL:         "https://github.com/owner/" + repository + "/pull/" + strconv.Itoa(number),
		HeadRefName: branch, BaseRefName: "main", State: "OPEN",
		UpdatedAt: now, ClosingIssues: []model.Issue{closing},
	}
}

func threadByID(t *testing.T, threads []model.Thread, id string) model.Thread {
	t.Helper()
	for _, thread := range threads {
		if thread.ID == id {
			return thread
		}
	}
	t.Fatalf("thread %s not found in %#v", id, threads)
	return model.Thread{}
}

func localLane(branch string, publication model.PublicationState, worktree model.Worktree) gitscan.LocalLane {
	return gitscan.LocalLane{ID: branch, Branch: branch, Publication: publication, Worktree: worktree}
}

type fakeGit struct {
	results map[string]gitscan.Result
}

func (f fakeGit) Scan(_ context.Context, repository config.Repository, _ bool, _ time.Duration) gitscan.Result {
	return f.results[repository.GitHub]
}

type fakeGitHub struct {
	results map[string]model.RemoteEvidence
}

func (f fakeGitHub) CollectRepository(
	_ context.Context,
	repository config.Repository,
	_, _ string,
	_ []int,
) model.RemoteEvidence {
	return f.results[repository.GitHub]
}

type countingGitHub struct {
	calls int
}

func (f *countingGitHub) CollectRepository(
	context.Context,
	config.Repository,
	string,
	string,
	[]int,
) model.RemoteEvidence {
	f.calls++
	return model.RemoteEvidence{Errors: []model.ScanError{{Stage: "github", Message: errors.New("unexpected call").Error()}}}
}

type fakeDiscoverer struct {
	result discovery.Result
}

func (f fakeDiscoverer) Discover(context.Context, []config.Source) discovery.Result {
	return f.result
}

type fakeMemory struct {
	results map[string]memoryscan.Result
}

func (f fakeMemory) Scan(path string) memoryscan.Result {
	return f.results[path]
}

type fakeStore struct {
	mu      sync.Mutex
	state   threadstate.State
	warning string
}

func (f *fakeStore) Load() (threadstate.State, string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.state, f.warning, nil
}

func (f *fakeStore) Write(state threadstate.State) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.state = state
	return nil
}

type failingInference struct {
	err error
}

func (f failingInference) Enrich(context.Context, string, []model.Thread) ([]model.InferenceThread, error) {
	return nil, f.err
}
