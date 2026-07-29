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

func issue(repository string, number int, title, state string, now time.Time) model.Issue {
	return model.Issue{
		Number: number, Title: title, Body: "Goal body", State: state,
		URL:       "https://github.com/owner/" + repository + "/issues/" + strconv.Itoa(number),
		UpdatedAt: now,
	}
}

func openPR(repository string, number int, title, branch string, closing model.Issue, now time.Time) model.PullRequest {
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

type countingMemory struct {
	calls  int
	result memoryscan.Result
}

func (f *countingMemory) Scan(string) memoryscan.Result {
	f.calls++
	return f.result
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

type successfulInference struct{}

func (successfulInference) Enrich(
	_ context.Context,
	_ string,
	threads []model.Thread,
) ([]model.InferenceThread, error) {
	values := make([]model.InferenceThread, 0, len(threads))
	for _, thread := range threads {
		values = append(values, model.InferenceThread{ThreadID: thread.ID})
	}
	return values, nil
}

type reviewDecisionInference struct{}

func (reviewDecisionInference) Enrich(
	_ context.Context,
	_ string,
	threads []model.Thread,
) ([]model.InferenceThread, error) {
	values := make([]model.InferenceThread, 0, len(threads))
	for _, thread := range threads {
		values = append(values, model.InferenceThread{
			ThreadID: thread.ID, ReviewSignificant: true, Confidence: 0.9,
			ReviewSummary: model.InferenceClaim{
				Text:        "Ownership must be decided before the contract changes.",
				EvidenceIDs: []string{"spec:0001"},
			},
		})
	}
	return values, nil
}
