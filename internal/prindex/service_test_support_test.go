package prindex

import (
	"context"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
)

type fakeProjectDiscoverer struct {
	result discovery.Result
}

func (f fakeProjectDiscoverer) Discover(
	context.Context,
	[]config.Source,
) discovery.Result {
	return f.result
}

type fakePullRequestClient struct {
	calls        int
	repositories [][]config.Repository
	results      map[string]RepositoryResult
	rateLimit    *GitHubRateLimit
}

func (f *fakePullRequestClient) ListOpen(
	_ context.Context,
	repositories []config.Repository,
) ClientResult {
	f.calls++
	f.repositories = append(
		f.repositories, append([]config.Repository(nil), repositories...),
	)
	return ClientResult{Repositories: f.results, RateLimit: f.rateLimit}
}

type memoryCacheStore struct {
	state        cacheState
	warning      string
	beforeUpdate func(*cacheState)
}

func (s *memoryCacheStore) Load() (cacheState, string, error) {
	return cloneCache(s.state), s.warning, nil
}

func (s *memoryCacheStore) Update(mutate func(*cacheState) bool) (cacheState, error) {
	state := cloneCache(s.state)
	if s.beforeUpdate != nil {
		s.beforeUpdate(&state)
	}
	if !mutate(&state) {
		// Match Store.Update: a callback that declines to commit still returns
		// the freshly loaded state, so a concurrent change is not discarded.
		return cloneCache(state), nil
	}
	s.state = state
	return cloneCache(state), nil
}
