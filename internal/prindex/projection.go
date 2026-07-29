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
