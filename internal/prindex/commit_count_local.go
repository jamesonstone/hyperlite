package prindex

import (
	"context"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

const localCommitCountTimeout = 5 * time.Second

func localCommitCount(ctx context.Context, git command.Runner, path string) (int, bool) {
	if git == nil || strings.TrimSpace(path) == "" {
		return 0, false
	}
	commandContext, cancel := context.WithTimeout(ctx, localCommitCountTimeout)
	defer cancel()
	output, err := git.Run(commandContext, path, "git", "rev-list", "--count", "HEAD")
	if err != nil {
		return 0, false
	}
	count, err := strconv.Atoi(strings.TrimSpace(string(output)))
	if err != nil || count < 0 {
		return 0, false
	}
	return count, true
}

func seedLocalCommitCounts(
	ctx context.Context,
	cache *cacheState,
	sources []config.Source,
	resolved map[string]config.Repository,
	git command.Runner,
	now time.Time,
) bool {
	if git == nil {
		return false
	}
	changed := false
	for _, source := range sources {
		repository, found := resolved[filepath.Clean(source.Path)]
		if !found || repository.GitHub == "" {
			continue
		}
		key := repositoryKey(repository.GitHub)
		entry := cache.Repositories[key]
		if entry.CommitCount != nil {
			continue
		}
		count, ok := localCommitCount(ctx, git, source.Path)
		if !ok {
			continue
		}
		entry.Repository = repository.GitHub
		entry.CommitCount = &count
		entry.CommitCountObservedAt = now
		entry.CommitCountSource = commitCountSourceLocal
		if entry.PullRequests == nil {
			entry.PullRequests = []model.ProjectPullRequest{}
		}
		cache.Repositories[key] = entry
		changed = true
	}
	return changed
}
