package prindex

import (
	"fmt"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

const (
	// Automatic (stale) refreshes pause below this share of the hourly
	// GraphQL quota, which Hyperlite shares with every other gh caller on the
	// machine. Explicit Refresh is never paused.
	automaticRefreshMinRemainingFraction = 0.20
	automaticRefreshMinRemainingFloor    = 1000
)

// automaticRefreshPause returns a warning when a stale refresh must not spend
// quota: the latest observation in the current window is below the floor.
func automaticRefreshPause(limit *model.GitHubRateLimit, mode RefreshMode, now time.Time) string {
	if mode != RefreshStale || limit == nil || !now.Before(limit.ResetAt) ||
		now.Sub(limit.ObservedAt) > maxRateLimitObservationAge {
		return ""
	}
	floor := max(
		automaticRefreshMinRemainingFloor,
		int(automaticRefreshMinRemainingFraction*float64(limit.Limit)),
	)
	if limit.Remaining >= floor {
		return ""
	}
	return fmt.Sprintf(
		"automatic refresh paused: %d GitHub GraphQL points remain (floor %d) until %s; Refresh still works",
		limit.Remaining, floor, limit.ResetAt.Local().Format("15:04"),
	)
}

// listingHints offers cached open sets for automatic refreshes so unchanged
// repositories cost only their probe. A forced refresh re-reads everything.
func listingHints(
	repositories []config.Repository,
	cache cacheState,
	mode RefreshMode,
	now time.Time,
) map[string]ListingHint {
	if mode == RefreshForce {
		return nil
	}
	hints := make(map[string]ListingHint)
	for _, repository := range repositories {
		key := repositoryKey(repository.GitHub)
		if hint, ok := listingHint(cache.Repositories[key], now); ok {
			hints[key] = hint
		}
	}
	return hints
}
