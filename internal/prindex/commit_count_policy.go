package prindex

import (
	"path/filepath"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

const (
	commitCountTTL              = 24 * time.Hour
	commitCountQuotaFloorPoints = 2000
	commitCountQuotaFraction    = 0.40
)

func commitCountNeedsGitHub(entry cacheEntry, now time.Time) bool {
	if entry.CommitCountSource != commitCountSourceGitHub {
		return true
	}
	if entry.CommitCountObservedAt.IsZero() {
		return true
	}
	return now.Sub(entry.CommitCountObservedAt) >= commitCountTTL
}

func hasExcessCommitCountQuota(limit *model.GitHubRateLimit, now time.Time) bool {
	if limit == nil {
		return false
	}
	if now.Sub(limit.ObservedAt) > maxRateLimitObservationAge {
		return false
	}
	remaining := limit.Remaining
	if !now.Before(limit.ResetAt) {
		remaining = limit.Limit
	}
	return remaining >= commitCountQuotaFloor(limit.Limit)
}

func commitCountQuotaFloor(limit int) int {
	floor := int(float64(limit) * commitCountQuotaFraction)
	if floor < commitCountQuotaFloorPoints {
		return commitCountQuotaFloorPoints
	}
	return floor
}

func repositoriesNeedingCommitCount(
	sources []config.Source,
	resolved map[string]config.Repository,
	cache cacheState,
	now time.Time,
) []config.Repository {
	seen := make(map[string]struct{})
	var result []config.Repository
	for _, source := range sources {
		repository, found := resolved[filepath.Clean(source.Path)]
		if !found || repository.GitHub == "" {
			continue
		}
		key := repositoryKey(repository.GitHub)
		if _, duplicate := seen[key]; duplicate {
			continue
		}
		if !commitCountNeedsGitHub(cache.Repositories[key], now) {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, repository)
	}
	return result
}
