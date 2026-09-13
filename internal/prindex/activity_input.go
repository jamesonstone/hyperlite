package prindex

import (
	"path/filepath"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func configuredRepositoryKeys(
	sources []config.Source,
	resolved map[string]config.Repository,
) map[string]struct{} {
	keys := make(map[string]struct{}, len(sources))
	for _, source := range sources {
		if repository, found := resolved[filepath.Clean(source.Path)]; found {
			keys[repositoryKey(repository.GitHub)] = struct{}{}
		}
	}
	return keys
}

func activityRequests(
	sources []config.Source,
	resolved map[string]config.Repository,
	cache cacheState,
) ([]ActivityRequest, int) {
	seen := map[string]struct{}{}
	var requests []ActivityRequest
	total := 0
	for _, source := range sources {
		repository, found := resolved[filepath.Clean(source.Path)]
		if !found {
			continue
		}
		key := repositoryKey(repository.GitHub)
		if _, duplicate := seen[key]; duplicate {
			continue
		}
		seen[key] = struct{}{}
		entry := cache.Repositories[key]
		if entry.Workflows == nil {
			continue
		}
		active := entry.Workflows.ActiveRunCount()
		if active == 0 {
			continue
		}
		total += active
		requests = append(requests, ActivityRequest{
			Repository:         repository,
			PullRequestNumbers: entry.Workflows.ActivePullRequestNumbers(),
		})
	}
	return requests, total
}

func activityInput(cache cacheState, activeCount int, now time.Time) activityPollInput {
	input := activityPollInput{RateLimit: cache.RateLimit, ActiveRunCount: activeCount, Now: now}
	if cache.Activity != nil {
		input.LastCheckedAt = cache.Activity.LastCheckedAt
		input.BurstStartedAt = cache.Activity.BurstStartedAt
		input.PollsThisWindow = activityWindowPolls(cache.Activity, cachedResetAt(cache))
	}
	return input
}

// activityPolicy reports what an automatic poll would decide right now so the
// native app can schedule without guessing.
func activityPolicy(scan scanContext) *model.ActivityPollDecision {
	_, activeCount := activityRequests(scan.sources, scan.resolved, scan.cache)
	decision := decideActivityPoll(defaultActivityPollPolicy, activityInput(scan.cache, activeCount, scan.now))
	return &decision
}

func cachedResetAt(cache cacheState) time.Time {
	if cache.RateLimit == nil {
		return time.Time{}
	}
	return cache.RateLimit.ResetAt
}
