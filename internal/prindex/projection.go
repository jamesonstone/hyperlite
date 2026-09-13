package prindex

import (
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func buildProject(
	source config.Source,
	repository config.Repository,
	cache cacheState,
	queryResults map[string]RepositoryResult,
	discoveryMessage string,
	mode RefreshMode,
	now time.Time,
) model.ProjectPullRequests {
	path := filepath.Clean(source.Path)
	project := model.ProjectPullRequests{
		ID: path, Name: filepath.Base(path), Path: path,
		Status:       model.ProjectPullRequestsUnavailable,
		PullRequests: []model.ProjectPullRequest{},
	}
	if repository.GitHub != "" {
		project.Name = repository.Name
		project.Repository = repository.GitHub
	} else if cachedRepository := cache.Projects[path]; cachedRepository != "" {
		project.Repository = cachedRepository
	}
	key := repositoryKey(project.Repository)
	entry, cached := cache.Repositories[key]
	if cached {
		project.Workflows = cloneWorkflowActivity(entry.Workflows)
		project.CommitCount = entry.CommitCount
	}
	hasObservation := cached && !entry.ObservedAt.IsZero()
	if cached && !entry.CheckedAt.IsZero() {
		checkedAt := entry.CheckedAt
		project.CheckedAt = &checkedAt
	} else if hasObservation {
		checkedAt := entry.ObservedAt
		project.CheckedAt = &checkedAt
	}
	if hasObservation {
		observedAt := entry.ObservedAt
		project.ObservedAt = &observedAt
		project.PullRequests = append(project.PullRequests, entry.PullRequests...)
	}
	if repository.GitHub == "" {
		if hasObservation {
			project.Status = model.ProjectPullRequestsCached
			project.Message = firstMessage(
				discoveryMessage,
				"GitHub repository is no longer available locally",
			)
		} else {
			project.Message = firstMessage(discoveryMessage, "GitHub repository is unavailable")
		}
		return project
	}
	if queried, found := queryResults[key]; found && queried.Error != "" {
		project.Message = queried.Error
		if hasObservation {
			project.Status = model.ProjectPullRequestsCached
		}
		return project
	}
	if !hasObservation {
		if entry.LastError != "" {
			project.Message = entry.LastError
			return project
		}
		project.Message = "No cached pull request data is available"
		return project
	}
	if entry.LastError != "" {
		project.Status = model.ProjectPullRequestsCached
		project.Message = entry.LastError
		return project
	}
	if mode == RefreshLocal && now.Sub(entry.ObservedAt) >= RefreshInterval {
		project.Status = model.ProjectPullRequestsCached
		project.Message = "Cached pull request data is older than five minutes"
		return project
	}
	project.Status = model.ProjectPullRequestsCurrent
	return project
}

// buildScanResult projects every configured source from the cache plus this
// scan's query results, folding per-project freshness into scan-level
// checked and observed times.
func buildScanResult(
	scan scanContext,
	queryResults map[string]RepositoryResult,
	mode RefreshMode,
) model.ProjectPullRequestScan {
	result := model.ProjectPullRequestScan{
		SchemaVersion: model.ProjectPullRequestScanSchemaVersion,
		GeneratedAt:   scan.now, RefreshIntervalSeconds: int64(RefreshInterval / time.Second),
		RateLimit: cloneRateLimit(scan.cache.RateLimit),
		Projects:  []model.ProjectPullRequests{},
		Errors:    []model.ScanError{}, Warnings: []model.ScanError{},
	}
	if scan.cacheWarning != "" {
		result.Warnings = append(result.Warnings, model.ScanError{
			Stage: "pull-request-cache", Message: scan.cacheWarning,
		})
	}
	warnings := warningsByPath(scan.discovered.Warnings)
	checksComplete := true
	for _, source := range scan.sources {
		repository := scan.resolved[filepath.Clean(source.Path)]
		project := buildProject(
			source, repository, scan.cache,
			queryResults, warnings[filepath.Clean(source.Path)], mode, scan.now,
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
	return result
}

func warningsByPath(warnings []discovery.Warning) map[string]string {
	result := make(map[string]string, len(warnings))
	for _, warning := range warnings {
		path := filepath.Clean(warning.Path)
		message := strings.TrimSpace(warning.Message)
		if result[path] == "" {
			result[path] = message
		}
	}
	return result
}

func firstMessage(values ...string) string {
	for _, value := range values {
		if value = strings.TrimSpace(value); value != "" {
			return value
		}
	}
	return ""
}

func sortProjectPullRequests(values []model.ProjectPullRequest) {
	sort.Slice(values, func(i, j int) bool {
		if !values[i].UpdatedAt.Equal(values[j].UpdatedAt) {
			return values[i].UpdatedAt.After(values[j].UpdatedAt)
		}
		return values[i].Number < values[j].Number
	})
}
