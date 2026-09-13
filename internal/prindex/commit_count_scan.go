package prindex

import (
	"context"
	"time"
)

func (s Scanner) refreshCommitCounts(
	ctx context.Context,
	scan *scanContext,
	mode RefreshMode,
) error {
	if mode == RefreshActivity {
		return nil
	}
	if s.Git != nil {
		updated, err := s.Store.Update(func(current *cacheState) bool {
			return seedLocalCommitCounts(
				ctx, current, scan.sources, scan.resolved, s.Git, scan.now,
			)
		})
		if err != nil {
			return err
		}
		scan.cache = updated
	}
	if mode == RefreshLocal || s.Sizes == nil {
		return nil
	}
	if !hasExcessCommitCountQuota(scan.cache.RateLimit, scan.now) {
		return nil
	}
	stale := repositoriesNeedingCommitCount(scan.sources, scan.resolved, scan.cache, scan.now)
	if len(stale) == 0 {
		return nil
	}
	result := s.Sizes.FetchCommitCounts(ctx, stale)
	updated, err := s.Store.Update(func(current *cacheState) bool {
		changed := applyCommitCounts(current, result, scan.now)
		if observed := observedRateLimit(result.RateLimit, scan.now); observed != nil {
			current.RateLimit = applyRateLimitBurnRate(observed, current.RateLimit)
			changed = true
		}
		return changed
	})
	if err != nil {
		return err
	}
	scan.cache = updated
	return nil
}

func applyCommitCounts(cache *cacheState, result CommitCountResult, now time.Time) bool {
	changed := false
	for key, fetched := range result.Repositories {
		if fetched.Error != "" {
			continue
		}
		entry, found := cache.Repositories[key]
		if !found {
			continue
		}
		count := fetched.Count
		entry.CommitCount = &count
		entry.CommitCountObservedAt = now
		entry.CommitCountSource = commitCountSourceGitHub
		cache.Repositories[key] = entry
		changed = true
	}
	return changed
}
