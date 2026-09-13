package prindex

import (
	"context"
	"errors"
	"path/filepath"
	"time"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

const RefreshInterval = 5 * time.Minute

type RefreshMode string

const (
	RefreshLocal    RefreshMode = "local"
	RefreshStale    RefreshMode = "stale"
	RefreshForce    RefreshMode = "force"
	RefreshActivity RefreshMode = "activity"
)

type RepositoryDiscoverer interface {
	Discover(context.Context, []config.Source) discovery.Result
}

type PullRequestClient interface {
	ListOpen(context.Context, []config.Repository) ClientResult
}

// WorkflowClient owns the two small follow-up queries: workflow catalogs for
// changed trees and the activity poll for repositories with running work.
type WorkflowClient interface {
	FetchCatalogs(context.Context, []config.Repository) CatalogResult
	PollActivity(context.Context, []ActivityRequest) ActivityResult
}

type CommitCountClient interface {
	FetchCommitCounts(context.Context, []config.Repository) CommitCountResult
}

type Scanner struct {
	Discovery RepositoryDiscoverer
	Client    PullRequestClient
	Workflows WorkflowClient
	Sizes     CommitCountClient
	Git       command.Runner
	Store     CacheStore
	Now       func() time.Time
}

// scanContext carries the shared inputs of one scan across refresh modes.
type scanContext struct {
	cache        cacheState
	cacheWarning string
	sources      []config.Source
	discovered   discovery.Result
	resolved     map[string]config.Repository
	now          time.Time
}

func New(runner command.Runner) Scanner {
	client := GitHubClient{Runner: runner}
	return Scanner{
		Discovery: discovery.Discoverer{Runner: runner},
		Client:    client,
		Workflows: client,
		Sizes:     client,
		Git:       runner,
		Store:     Store{},
		Now:       time.Now,
	}
}

func (s Scanner) Scan(
	ctx context.Context,
	cfg config.Config,
	mode RefreshMode,
) (model.ProjectPullRequestScan, error) {
	if s.Discovery == nil || s.Store == nil {
		return model.ProjectPullRequestScan{}, errors.New("pull request scanner is not fully configured")
	}
	switch mode {
	case RefreshLocal, RefreshStale, RefreshForce, RefreshActivity:
	default:
		return model.ProjectPullRequestScan{}, errors.New("invalid pull request refresh mode")
	}
	if s.Now == nil {
		s.Now = time.Now
	}
	now := s.Now().UTC()
	cache, cacheWarning, err := s.Store.Load()
	if err != nil {
		return model.ProjectPullRequestScan{}, err
	}
	sources := configuredProjectSources(cfg)
	discovered := s.Discovery.Discover(ctx, sources)
	scan := scanContext{
		cache: cache, cacheWarning: cacheWarning, sources: sources,
		discovered: discovered, resolved: repositoriesByPath(discovered.Repositories), now: now,
	}
	if mode == RefreshActivity {
		return s.scanActivity(ctx, scan)
	}
	queryResults := map[string]RepositoryResult{}
	if mode != RefreshLocal {
		if s.Client == nil {
			return model.ProjectPullRequestScan{}, errors.New("pull request client is not configured")
		}
		var rateLimit *GitHubRateLimit
		var catalogs map[string]CatalogEntry
		repositories := repositoriesToRefresh(sources, scan.resolved, cache, mode, now)
		if len(repositories) > 0 {
			clientResult := s.Client.ListOpen(ctx, repositories)
			queryResults = clientResult.Repositories
			if queryResults == nil {
				queryResults = make(map[string]RepositoryResult, len(repositories))
			}
			for _, repository := range repositories {
				key := repositoryKey(repository.GitHub)
				if _, found := queryResults[key]; !found {
					queryResults[key] = RepositoryResult{
						Error: "GitHub returned no pull request result",
					}
				}
			}
			rateLimit = clientResult.RateLimit
			catalogs, rateLimit = s.fetchChangedCatalogs(ctx, repositories, queryResults, cache, rateLimit)
		}
		scan.cache, err = s.Store.Update(func(current *cacheState) bool {
			updateProjectMappings(current, sources, scan.resolved)
			applyQueryResults(current, repositories, queryResults, catalogs, now)
			recordActivityBurst(current, configuredRepositoryKeys(sources, scan.resolved), now)
			if observed := observedRateLimit(rateLimit, now); observed != nil {
				current.RateLimit = applyRateLimitBurnRate(observed, current.RateLimit)
			}
			return true
		})
		if err != nil {
			return model.ProjectPullRequestScan{}, err
		}
	}
	if err := s.refreshCommitCounts(ctx, &scan, mode); err != nil {
		return model.ProjectPullRequestScan{}, err
	}
	result := buildScanResult(scan, queryResults, mode)
	result.ActivityPolicy = activityPolicy(scan)
	return result, nil
}

func configuredProjectSources(cfg config.Config) []config.Source {
	if len(cfg.Projects) > 0 {
		return append([]config.Source(nil), cfg.Projects...)
	}
	return append([]config.Source(nil), cfg.Sources...)
}

func repositoriesByPath(repositories []config.Repository) map[string]config.Repository {
	result := make(map[string]config.Repository, len(repositories))
	for _, repository := range repositories {
		result[filepath.Clean(repository.Path)] = repository
	}
	return result
}

func repositoriesToRefresh(
	sources []config.Source,
	resolved map[string]config.Repository,
	cache cacheState,
	mode RefreshMode,
	now time.Time,
) []config.Repository {
	seen := make(map[string]struct{})
	var result []config.Repository
	for _, source := range sources {
		repository, found := resolved[filepath.Clean(source.Path)]
		if !found {
			continue
		}
		key := repositoryKey(repository.GitHub)
		if _, duplicate := seen[key]; duplicate {
			continue
		}
		entry, cached := cache.Repositories[key]
		if cached && entry.LastError == "" && cacheEntryNeedsHydration(entry) {
			cached = false
		}
		lastCheck := entry.CheckedAt
		if lastCheck.IsZero() {
			lastCheck = entry.ObservedAt
		}
		if mode != RefreshForce && cached && !lastCheck.IsZero() &&
			now.Sub(lastCheck) < RefreshInterval {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, repository)
	}
	return result
}

// cacheEntryNeedsHydration reports whether a successful legacy entry predates
// a projection field and must refresh once inside the five-minute floor.
func cacheEntryNeedsHydration(entry cacheEntry) bool {
	return cacheEntryNeedsHeadRefs(entry) ||
		cacheEntryNeedsReviewCounts(entry) ||
		cacheEntryNeedsWorkflowActivity(entry)
}

func cacheEntryNeedsHeadRefs(entry cacheEntry) bool {
	for _, pullRequest := range entry.PullRequests {
		if pullRequest.HeadRefName == "" || pullRequest.HeadRefOID == "" {
			return true
		}
	}
	return false
}

func cacheEntryNeedsReviewCounts(entry cacheEntry) bool {
	for _, pullRequest := range entry.PullRequests {
		if pullRequest.UnresolvedReviewThreads == nil {
			return true
		}
	}
	return false
}

func cacheEntryNeedsWorkflowActivity(entry cacheEntry) bool {
	return entry.Workflows == nil
}

func updateProjectMappings(
	cache *cacheState,
	sources []config.Source,
	resolved map[string]config.Repository,
) {
	for _, source := range sources {
		path := filepath.Clean(source.Path)
		if repository, found := resolved[path]; found {
			cache.Projects[path] = repository.GitHub
		}
	}
}

func applyQueryResults(
	cache *cacheState,
	repositories []config.Repository,
	results map[string]RepositoryResult,
	catalogs map[string]CatalogEntry,
	now time.Time,
) {
	for _, repository := range repositories {
		result, found := results[repositoryKey(repository.GitHub)]
		if !found {
			continue
		}
		key := repositoryKey(repository.GitHub)
		entry := cache.Repositories[key]
		entry.Repository = repository.GitHub
		entry.CheckedAt = now
		entry.LastError = result.Error
		if result.Error != "" {
			if entry.PullRequests == nil {
				entry.PullRequests = []model.ProjectPullRequest{}
			}
			cache.Repositories[key] = entry
			continue
		}
		pullRequests := append(
			[]model.ProjectPullRequest(nil), result.PullRequests...,
		)
		sortProjectPullRequests(pullRequests)
		entry.ObservedAt = now
		entry.LastError = ""
		entry.PullRequests = pullRequests
		var catalog *CatalogEntry
		if fetched, hasCatalog := catalogs[key]; hasCatalog {
			catalog = &fetched
		}
		entry.Workflows = refreshedWorkflowActivity(entry.Workflows, result.Activity, catalog, now)
		cache.Repositories[key] = entry
	}
}
