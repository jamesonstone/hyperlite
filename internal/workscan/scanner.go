package workscan

import (
	"context"
	"errors"
	"sync"
	"time"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/githubscan"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/inference"
	"github.com/jamesonstone/hyperlite/internal/memoryscan"
	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/threadbuild"
	"github.com/jamesonstone/hyperlite/internal/threadstate"
)

type GitScanner interface {
	Scan(context.Context, config.Repository, bool, time.Duration) gitscan.Result
}

type GitHubClient interface {
	CollectRepository(context.Context, config.Repository, string, string, []int) model.RemoteEvidence
}

type RepositoryDiscoverer interface {
	Discover(context.Context, []config.Source) discovery.Result
}

type MemoryLoader interface {
	Scan(string) memoryscan.Result
}

type StateStore interface {
	Load() (threadstate.State, string, error)
	Write(threadstate.State) error
}

type InferenceClient interface {
	Enrich(context.Context, string, []model.Thread) ([]model.InferenceThread, error)
}

type Scanner struct {
	Git       GitScanner
	GitHub    GitHubClient
	Discovery RepositoryDiscoverer
	Memory    MemoryLoader
	Store     StateStore
	Inference InferenceClient
	Now       func() time.Time
}

type memoryLoader struct{}

func (memoryLoader) Scan(path string) memoryscan.Result { return memoryscan.Scan(path) }

// New creates Hyperlite's selected-project evidence scanner.
func New(runner command.Runner) Scanner {
	return Scanner{
		Git:       gitscan.Scanner{Runner: runner, Now: time.Now},
		GitHub:    githubscan.Client{Runner: runner, Now: time.Now},
		Discovery: discovery.Discoverer{Runner: runner},
		Memory:    memoryLoader{},
		Store:     threadstate.Store{},
		Inference: inference.Client{},
		Now:       time.Now,
	}
}

type repositoryResult struct {
	index      int
	threads    []model.Thread
	remote     *threadstate.RemoteCache
	errors     []model.ScanError
	warnings   []model.ScanError
	repository config.Repository
}

func (s Scanner) Scan(ctx context.Context, cfg config.Config, refresh, _ bool) (model.ThreadScan, error) {
	return s.scan(ctx, cfg, refresh, true)
}

func (s Scanner) ScanLocal(ctx context.Context, cfg config.Config, _ bool) (model.ThreadScan, error) {
	return s.scan(ctx, cfg, false, false)
}

// Infer enriches the cached deterministic snapshot with bounded local-model
// synthesis. It never performs GitHub or fetch operations.
func (s Scanner) Infer(ctx context.Context, cfg config.Config) (model.ThreadScan, error) {
	result, err := s.ScanLocal(ctx, cfg, false)
	if err != nil {
		return model.ThreadScan{}, err
	}
	if cfg.Settings.OllamaModel == "" {
		for index := range result.Threads {
			result.Threads[index].InferenceStatus = "not_configured"
		}
		return result, nil
	}
	if s.Inference == nil {
		return model.ThreadScan{}, errors.New("thread inference is not configured")
	}
	state, _, err := s.Store.Load()
	if err != nil {
		return model.ThreadScan{}, err
	}
	var pending []model.Thread
	for index := range result.Threads {
		thread := &result.Threads[index]
		if !thread.Active {
			continue
		}
		evidenceDigest := threadstate.EvidenceDigest(*thread)
		if _, found := threadstate.CachedInference(state, thread.ID, evidenceDigest); !found {
			pending = append(pending, *thread)
		}
	}
	if len(pending) == 0 {
		return result, nil
	}
	values, inferenceErr := s.Inference.Enrich(ctx, cfg.Settings.OllamaModel, pending)
	if inferenceErr != nil {
		for index := range result.Threads {
			if result.Threads[index].Active {
				result.Threads[index].InferenceStatus = "unavailable"
			}
		}
		result.Warnings = append(result.Warnings, model.ScanError{
			Stage: "local-inference", Message: inferenceErr.Error(),
		})
		finalizeScan(&result)
		return result, nil
	}
	if s.Now == nil {
		s.Now = time.Now
	}
	now := s.Now().UTC()
	digests := make(map[string]string, len(pending))
	for _, thread := range pending {
		digests[thread.ID] = threadstate.EvidenceDigest(thread)
	}
	for _, value := range values {
		threadstate.SetInference(&state, value.ThreadID, digests[value.ThreadID], value, now)
	}
	if err := s.Store.Write(state); err != nil {
		return model.ThreadScan{}, err
	}
	inferred := make(map[string]model.InferenceThread, len(values))
	for _, value := range values {
		inferred[value.ThreadID] = value
	}
	for index := range result.Threads {
		if value, exists := inferred[result.Threads[index].ID]; exists {
			applyInference(&result.Threads[index], value)
			result.Threads[index].InferenceStatus = "current"
		}
	}
	finalizeScan(&result)
	return result, nil
}

func (s Scanner) scan(ctx context.Context, cfg config.Config, refresh, includeRemote bool) (model.ThreadScan, error) {
	if s.Git == nil || s.GitHub == nil || s.Discovery == nil || s.Memory == nil || s.Store == nil {
		return model.ThreadScan{}, errors.New("thread scanner is not fully configured")
	}
	if s.Now == nil {
		s.Now = time.Now
	}
	now := s.Now().UTC()
	state, stateWarning, err := s.Store.Load()
	if err != nil {
		return model.ThreadScan{}, err
	}
	discovered := s.Discovery.Discover(ctx, cfg.Sources)
	repositories := selectedRepositories(cfg.Repositories, discovered.Repositories)
	result := model.ThreadScan{
		SchemaVersion: model.ThreadScanSchemaVersion, GeneratedAt: now,
		RemoteRefreshIntervalSeconds: int64(cfg.Settings.RemoteRefreshInterval / time.Second),
		Threads:                      []model.Thread{}, Errors: []model.ScanError{},
		Warnings: discoveryWarnings(discovered.Warnings),
	}
	result.Summary.Projects = len(repositories)
	if stateWarning != "" {
		result.Warnings = append(result.Warnings, model.ScanError{Stage: "thread-state", Message: stateWarning})
	}
	if len(repositories) == 0 {
		finalizeScan(&result)
		return result, nil
	}

	results := make(chan repositoryResult, len(repositories))
	semaphore := make(chan struct{}, max(1, cfg.Settings.MaxParallel))
	var waitGroup sync.WaitGroup
	for index, repository := range repositories {
		waitGroup.Add(1)
		go func() {
			defer waitGroup.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()
			results <- s.scanRepository(ctx, cfg, index, repository, refresh, includeRemote, state, now)
		}()
	}
	waitGroup.Wait()
	close(results)
	ordered := make([]repositoryResult, len(repositories))
	for repository := range results {
		ordered[repository.index] = repository
	}
	for _, repository := range ordered {
		result.Threads = append(result.Threads, repository.threads...)
		result.Errors = append(result.Errors, repository.errors...)
		result.Warnings = append(result.Warnings, repository.warnings...)
		if repository.remote != nil {
			state.Remote[repository.repository.GitHub] = *repository.remote
		}
	}
	resolveRelations(result.Threads)
	applyCachedInferences(&state, result.Threads)
	selectedGitHub := make([]string, 0, len(repositories))
	for _, repository := range repositories {
		selectedGitHub = append(selectedGitHub, repository.GitHub)
	}
	result.Threads = threadstate.ReconcileSelected(&state, result.Threads, selectedGitHub, now)
	if err := s.Store.Write(state); err != nil {
		return model.ThreadScan{}, err
	}
	result.RemoteObservedAt = oldestRemoteObservation(state, repositories)
	finalizeScan(&result)
	return result, nil
}

func (s Scanner) scanRepository(
	ctx context.Context,
	cfg config.Config,
	index int,
	repository config.Repository,
	refresh bool,
	includeRemote bool,
	state threadstate.State,
	now time.Time,
) repositoryResult {
	local := s.Git.Scan(ctx, repository, refresh, cfg.Settings.RemoteRefreshInterval)
	documents := s.scanRepositoryMemory(repository, local.Lanes)
	remote, remoteStale, cache := s.remoteEvidence(
		ctx, cfg, repository, local.Lanes, documents.Documents, includeRemote, state, now,
	)
	errors := append([]model.ScanError{}, local.Errors...)
	warnings := append([]model.ScanError{}, local.Warnings...)
	errors = append(errors, remote.Errors...)
	warnings = append(warnings, remote.Warnings...)
	for _, diagnostic := range documents.Diagnostics {
		warnings = append(warnings, model.ScanError{
			Repository: repository.Name, RepositoryPath: repository.Path,
			Stage: "repository-memory", Message: diagnostic.Path + ": " + diagnostic.Message,
		})
	}
	threads := threadbuild.Build(threadbuild.Input{
		Repository: repository, Locals: local.Lanes, Remote: remote,
		Documents: documents.Documents, RemoteStale: remoteStale, Now: now,
	})
	return repositoryResult{
		index: index, threads: threads, remote: cache,
		errors: errors, warnings: warnings, repository: repository,
	}
}
