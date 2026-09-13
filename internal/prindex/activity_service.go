package prindex

import (
	"context"
	"errors"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

// scanActivity is the bounded follow-up poll. It never lists pull requests
// or reads workflow files, and a denied governor decision touches neither
// GitHub nor the cache.
func (s Scanner) scanActivity(
	ctx context.Context,
	scan scanContext,
) (model.ProjectPullRequestScan, error) {
	requests, activeCount := activityRequests(scan.sources, scan.resolved, scan.cache)
	// Reserve the poll atomically: re-evaluate the governor and record the
	// reservation inside one locked Update before touching GitHub. Two
	// concurrent scans that both loaded the same state cannot both reach
	// PollActivity, because the second sees the first's recorded poll and is
	// denied on the minimum-interval or window cap.
	var decision model.ActivityPollDecision
	var reserved, missingClient bool
	reservedCache, err := s.Store.Update(func(current *cacheState) bool {
		decision = decideActivityPoll(
			defaultActivityPollPolicy, activityInput(*current, activeCount, scan.now),
		)
		if !decision.Allowed {
			return false
		}
		if s.Workflows == nil {
			missingClient = true
			return false
		}
		if current.Activity == nil {
			current.Activity = &cachedActivityState{}
		}
		recordActivityPoll(current.Activity, cachedResetAt(*current), scan.now)
		reserved = true
		return true
	})
	if err != nil {
		return model.ProjectPullRequestScan{}, err
	}
	if missingClient {
		return model.ProjectPullRequestScan{}, errors.New("workflow activity client is not configured")
	}
	// Use the cache the reservation Update loaded under the lock even when the
	// reservation was denied: the outer Load and this Update are separate
	// operations, so a concurrent scan can commit activity in between, and the
	// denied branch must not rebuild the result from the stale outer load.
	scan.cache = reservedCache
	if reserved {
		// The reservation stands even if PollActivity fails: a burned interval
		// is preferable to a race that ignores the cap on retry.
		polled := s.Workflows.PollActivity(ctx, requests)
		applied, updateErr := s.Store.Update(func(current *cacheState) bool {
			applyActivityResult(current, requests, polled, scan.now)
			recordActivityBurst(current, configuredRepositoryKeys(scan.sources, scan.resolved), scan.now)
			if observed := observedRateLimit(polled.RateLimit, scan.now); observed != nil {
				current.RateLimit = applyRateLimitBurnRate(observed, current.RateLimit)
			}
			return true
		})
		if updateErr != nil {
			return model.ProjectPullRequestScan{}, updateErr
		}
		scan.cache = applied
		decision.LastCheckedAt = optionalTime(scan.now)
		decision.PollsThisWindow = activityWindowPolls(applied.Activity, cachedResetAt(applied))
	}
	result := buildScanResult(scan, map[string]RepositoryResult{}, RefreshLocal)
	result.ActivityPolicy = &decision
	return result, nil
}

// fetchChangedCatalogs reads workflow files only for repositories whose
// workflows tree OID differs from the cached catalog.
func (s Scanner) fetchChangedCatalogs(
	ctx context.Context,
	repositories []config.Repository,
	results map[string]RepositoryResult,
	cache cacheState,
	rateLimit *GitHubRateLimit,
) (map[string]CatalogEntry, *GitHubRateLimit) {
	var changed []config.Repository
	for _, repository := range repositories {
		key := repositoryKey(repository.GitHub)
		result := results[key]
		if result.Error != "" || result.Activity == nil || result.Activity.TreeOID == "" {
			continue
		}
		entry := cache.Repositories[key]
		if entry.Workflows != nil && entry.Workflows.TreeOID == result.Activity.TreeOID {
			continue
		}
		changed = append(changed, repository)
	}
	if len(changed) == 0 || s.Workflows == nil {
		return nil, rateLimit
	}
	catalogs := s.Workflows.FetchCatalogs(ctx, changed)
	if catalogs.RateLimit != nil {
		rateLimit = catalogs.RateLimit
	}
	return catalogs.Repositories, rateLimit
}

// refreshedWorkflowActivity replaces observed runs and deployments after a
// full refresh. A failed catalog fetch keeps the previous catalog and clears
// the tree OID so the next refresh retries.
func refreshedWorkflowActivity(
	existing *model.ProjectWorkflowActivity,
	activity *repositoryActivity,
	catalog *CatalogEntry,
	now time.Time,
) *model.ProjectWorkflowActivity {
	if activity == nil {
		activity = &repositoryActivity{}
	}
	observed := now.UTC()
	next := &model.ProjectWorkflowActivity{
		Runs:        append(append([]model.WorkflowRun{}, activity.TipRuns...), activity.PullRequestRuns...),
		Deployments: append([]model.Deployment{}, activity.Deployments...),
		TreeOID:     activity.TreeOID,
		CheckedAt:   &observed, ObservedAt: &observed,
	}
	if existing != nil && existing.TreeOID == activity.TreeOID {
		next.Catalog = append([]model.WorkflowDefinition{}, existing.Catalog...)
	}
	next.Message = activity.Message
	switch {
	case catalog == nil:
		// A changed tree without a catalog result must not be recorded as
		// current, or the catalog would never be fetched.
		if existing == nil || existing.TreeOID != activity.TreeOID {
			if existing != nil {
				next.Catalog = append([]model.WorkflowDefinition{}, existing.Catalog...)
			}
			next.TreeOID = ""
		}
	case catalog.Error != "":
		next.Message = catalog.Error
		next.TreeOID = ""
		if existing != nil {
			next.Catalog = append([]model.WorkflowDefinition{}, existing.Catalog...)
		}
	default:
		next.Catalog = append([]model.WorkflowDefinition{}, catalog.Catalog...)
		next.TreeOID = catalog.TreeOID
	}
	normalizeWorkflowActivity(next)
	return next
}

func applyActivityResult(
	cache *cacheState,
	requests []ActivityRequest,
	polled ActivityResult,
	now time.Time,
) {
	checked := now.UTC()
	for _, request := range requests {
		key := repositoryKey(request.Repository.GitHub)
		entry, found := cache.Repositories[key]
		if !found || entry.Workflows == nil {
			continue
		}
		activity := cloneWorkflowActivity(entry.Workflows)
		result, polledRepository := polled.Repositories[key]
		if !polledRepository {
			result = RepositoryActivityResult{Error: "GitHub returned no activity result"}
		}
		activity.CheckedAt = &checked
		if result.Error != "" {
			activity.Message = result.Error
		} else {
			// The poll always asks for the default branch, so its tip runs
			// replace the cached ones even when GitHub returned no branch.
			activity.Runs = mergeActivityRuns(
				activity.Runs, true, result.TipRuns,
				result.PullRequestRuns, result.DroppedPullRequests,
			)
			activity.Deployments = append([]model.Deployment{}, result.Deployments...)
			activity.ObservedAt = &checked
			activity.Message = ""
		}
		normalizeWorkflowActivity(activity)
		entry.Workflows = activity
		cache.Repositories[key] = entry
	}
}

// recordActivityBurst starts the burst clock when running work is first
// observed in a configured repository, restarts it when work newer than the
// burst appears, and clears it once nothing is running. Polls call it too so
// a poll that observes completion closes the burst.
func recordActivityBurst(cache *cacheState, configured map[string]struct{}, now time.Time) {
	var latestStart time.Time
	active := 0
	for key, entry := range cache.Repositories {
		if _, watched := configured[key]; !watched || entry.Workflows == nil {
			continue
		}
		for _, run := range entry.Workflows.Runs {
			if run.IsActive() {
				active++
				latestStart = laterTime(latestStart, run.CreatedAt)
			}
		}
		for _, deployment := range entry.Workflows.Deployments {
			if deployment.IsActive() {
				active++
				latestStart = laterTime(latestStart, deployment.CreatedAt)
			}
		}
	}
	if active == 0 {
		if cache.Activity != nil {
			cache.Activity.BurstStartedAt = time.Time{}
		}
		return
	}
	if cache.Activity == nil {
		cache.Activity = &cachedActivityState{}
	}
	if cache.Activity.BurstStartedAt.IsZero() || latestStart.After(cache.Activity.BurstStartedAt) {
		cache.Activity.BurstStartedAt = now.UTC()
	}
}

func laterTime(a, b time.Time) time.Time {
	if b.After(a) {
		return b
	}
	return a
}
