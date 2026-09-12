package prindex

import (
	"context"
	"errors"
	"path/filepath"
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
	decision := decideActivityPoll(defaultActivityPollPolicy, activityInput(scan.cache, activeCount, scan.now))
	if decision.Allowed {
		if s.Workflows == nil {
			return model.ProjectPullRequestScan{}, errors.New("workflow activity client is not configured")
		}
		polled := s.Workflows.PollActivity(ctx, requests)
		cache, err := s.Store.Update(func(current *cacheState) {
			applyActivityResult(current, requests, polled, scan.now)
			recordActivityBurst(current, configuredRepositoryKeys(scan.sources, scan.resolved), scan.now)
			if observed := observedRateLimit(polled.RateLimit, scan.now); observed != nil {
				current.RateLimit = applyRateLimitBurnRate(observed, current.RateLimit)
			}
			if current.Activity == nil {
				current.Activity = &cachedActivityState{}
			}
			recordActivityPoll(current.Activity, cachedResetAt(*current), scan.now)
		})
		if err != nil {
			return model.ProjectPullRequestScan{}, err
		}
		scan.cache = cache
		decision.LastCheckedAt = optionalTime(scan.now)
		decision.PollsThisWindow = activityWindowPolls(cache.Activity, cachedResetAt(cache))
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
