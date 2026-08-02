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
	RefreshLocal RefreshMode = "local"
	RefreshStale RefreshMode = "stale"
	RefreshForce RefreshMode = "force"
)

type RepositoryDiscoverer interface {
	Discover(context.Context, []config.Source) discovery.Result
}

type PullRequestClient interface {
	ListOpen(context.Context, []config.Repository) ClientResult
}

type Scanner struct {
	Discovery RepositoryDiscoverer
	Client    PullRequestClient
	Store     CacheStore
	Now       func() time.Time
}

func New(runner command.Runner) Scanner {
	return Scanner{
		Discovery: discovery.Discoverer{Runner: runner},
		Client:    GitHubClient{Runner: runner},
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
	if mode != RefreshLocal && mode != RefreshStale && mode != RefreshForce {
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
	resolved := repositoriesByPath(discovered.Repositories)
	queryResults := map[string]RepositoryResult{}
	var rateLimit *GitHubRateLimit

	if mode != RefreshLocal {
		if s.Client == nil {
			return model.ProjectPullRequestScan{}, errors.New("pull request client is not configured")
		}
		repositories := repositoriesToRefresh(sources, resolved, cache, mode, now)
		if len(repositories) > 0 {
			clientResult := s.Client.ListOpen(ctx, repositories)
			queryResults = clientResult.Repositories
			if queryResults == nil {
				queryResults = make(map[string]RepositoryResult, len(repositories))
			}
			rateLimit = clientResult.RateLimit
			for _, repository := range repositories {
				key := repositoryKey(repository.GitHub)
				if _, found := queryResults[key]; !found {
					queryResults[key] = RepositoryResult{
						Error: "GitHub returned no pull request result",
					}
				}
			}
		}
		cache, err = s.Store.Update(func(current *cacheState) {
			updateProjectMappings(current, sources, resolved)
			applyQueryResults(current, repositories, queryResults, now)
			if observed := observedRateLimit(rateLimit, now); observed != nil {
				current.RateLimit = deriveRateLimitBurnRate(observed, current.RateLimit)
			}
		})
		if err != nil {
			return model.ProjectPullRequestScan{}, err
		}
	}

	result := model.ProjectPullRequestScan{
		SchemaVersion: model.ProjectPullRequestScanSchemaVersion,
		GeneratedAt:   now, RefreshIntervalSeconds: int64(RefreshInterval / time.Second),
		RateLimit: cloneRateLimit(cache.RateLimit),
		Projects:  []model.ProjectPullRequests{},
		Errors:    []model.ScanError{}, Warnings: []model.ScanError{},
	}
	if cacheWarning != "" {
		result.Warnings = append(result.Warnings, model.ScanError{
			Stage: "pull-request-cache", Message: cacheWarning,
		})
	}
	warnings := warningsByPath(discovered.Warnings)
	checksComplete := true
	for _, source := range sources {
		repository := resolved[filepath.Clean(source.Path)]
		project := buildProject(
			source, repository, cache,
			queryResults, warnings[filepath.Clean(source.Path)], mode, now,
		)
		result.Projects = append(result.Projects, project)
		if repository.GitHub != "" {
			if project.CheckedAt == nil {
				checksComplete = false
			} else if result.CheckedAt == nil ||
				project.CheckedAt.Before(*result.CheckedAt) {
				checkedAt := *project.CheckedAt
				result.CheckedAt = &checkedAt
			}
		}
		if project.ObservedAt != nil &&
			(result.ObservedAt == nil || project.ObservedAt.Before(*result.ObservedAt)) {
			observedAt := *project.ObservedAt
			result.ObservedAt = &observedAt
		}
	}
	if !checksComplete {
		result.CheckedAt = nil
	}
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
		if cached && entry.CheckedAt.IsZero() && cacheEntryNeedsHeadRefs(entry) {
			cached = false
		}
		if cached && entry.LastError == "" && cacheEntryNeedsReviewCounts(entry) {
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

func cacheEntryNeedsHeadRefs(entry cacheEntry) bool {
	for _, pullRequest := range entry.PullRequests {
		if pullRequest.HeadRefName == "" {
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
		cache.Repositories[key] = entry
	}
}
