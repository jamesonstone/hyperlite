package prindex

import (
	"context"
	"sync"

	"github.com/jamesonstone/hyperlite/internal/config"
)

// pullRequestConcurrency bounds parallel gh processes so a large watch list
// stays fast without tripping GitHub's secondary rate limits.
const pullRequestConcurrency = 10

// listCollector merges concurrent probe and detail outcomes.
type listCollector struct {
	mutex     sync.Mutex
	results   map[string]RepositoryResult
	rateLimit rateLimitCollector
}

func (l *listCollector) add(results map[string]RepositoryResult, rateLimit rateLimitCollector) {
	l.mutex.Lock()
	defer l.mutex.Unlock()
	for key, result := range results {
		l.results[key] = result
	}
	l.rateLimit.merge(rateLimit)
}

// ListOpen probes repositories cheaply in batches, then reads pull request
// details one repository per query, only where the probe found open pull
// requests or failed. Each repository is queried separately because one
// repository costs about a second of GitHub server time: a single batched
// query for 23 repositories exceeded GitHub's gateway timeout and failed every
// repository with HTTP 502. Detail queries start as soon as their probe batch
// returns.
func (c GitHubClient) ListOpen(
	ctx context.Context,
	repositories []config.Repository,
) ClientResult {
	return c.ListOpenReusing(ctx, repositories, nil)
}

// ListOpenReusing is ListOpen that skips the detail query for repositories
// whose probe matches their cached ListingHint.
func (c GitHubClient) ListOpenReusing(
	ctx context.Context,
	repositories []config.Repository,
	hints map[string]ListingHint,
) ClientResult {
	unique := uniqueRepositories(repositories)
	collected := listCollector{results: make(map[string]RepositoryResult, len(unique))}
	var group sync.WaitGroup
	slots := make(chan struct{}, pullRequestConcurrency)
	spawn := func(work func()) {
		group.Add(1)
		go func() {
			defer group.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			work()
		}()
	}
	for start := 0; start < len(unique); start += probeBatchSize {
		batch := unique[start:min(start+probeBatchSize, len(unique))]
		spawn(func() {
			probes, probeRateLimit := c.probeBatch(ctx, batch, hints)
			final := make(map[string]RepositoryResult, len(batch))
			for _, repository := range batch {
				key := repositoryKey(repository.GitHub)
				probe, found := probes[key]
				if found && probe.final {
					final[key] = probe.result
					continue
				}
				request := pageRequest{repository: repository, page: 1, pageSize: probe.openCount}
				spawn(func() { collected.add(c.collectRepository(ctx, request)) })
			}
			collected.add(final, probeRateLimit)
		})
	}
	group.Wait()
	return ClientResult{Repositories: collected.results, RateLimit: collected.rateLimit.latest}
}

func (c GitHubClient) collectRepository(
	ctx context.Context,
	request pageRequest,
) (map[string]RepositoryResult, rateLimitCollector) {
	results := make(map[string]RepositoryResult, 1)
	var collector rateLimitCollector
	c.collectBatch(ctx, []pageRequest{request}, results, &collector)
	return results, collector
}
