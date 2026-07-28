package workscan

import (
	"context"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/memoryscan"
	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/threadstate"
)

func (s Scanner) remoteEvidence(
	ctx context.Context,
	cfg config.Config,
	repository config.Repository,
	locals []gitscan.LocalLane,
	documents []memoryscan.Document,
	includeRemote bool,
	state threadstate.State,
	now time.Time,
) (model.RemoteEvidence, bool, *threadstate.RemoteCache) {
	cached, cachedFound := state.Remote[repository.GitHub]
	if !includeRemote {
		if !cachedFound {
			return emptyRemote(), false, nil
		}
		return cached.Evidence, now.Sub(cached.ObservedAt) > cfg.Settings.StaleAfter, nil
	}
	current := s.GitHub.CollectRepository(
		ctx, repository, string(cfg.Settings.GitHubScope), cfg.Settings.GitHubAuthor,
		anchoredIssueNumbers(repository, locals, documents),
	)
	if len(current.Errors) > 0 && cachedFound {
		errors := append([]model.ScanError{}, current.Errors...)
		stale := cached.Evidence
		stale.Errors = append(stale.Errors, errors...)
		return stale, true, nil
	}
	current = boundedRemoteHistory(current, cached, cachedFound, locals, documents)
	cache := &threadstate.RemoteCache{ObservedAt: now, Evidence: current}
	return current, false, cache
}

func anchoredIssueNumbers(
	repository config.Repository,
	locals []gitscan.LocalLane,
	documents []memoryscan.Document,
) []int {
	numbers := make(map[int]struct{})
	for _, local := range locals {
		for _, branch := range []string{local.Branch, gitscan.IdentityBranch(local)} {
			if number := gitscan.IssueNumber(branch); number > 0 {
				numbers[number] = struct{}{}
			}
		}
	}
	for _, document := range documents {
		for _, rawURL := range document.IssueURLs {
			parsed, err := url.Parse(rawURL)
			if err != nil || !strings.EqualFold(parsed.Host, "github.com") {
				continue
			}
			parts := strings.Split(strings.Trim(parsed.Path, "/"), "/")
			if len(parts) != 4 || parts[2] != "issues" ||
				!strings.EqualFold(parts[0]+"/"+parts[1], repository.GitHub) {
				continue
			}
			if number, err := strconv.Atoi(parts[3]); err == nil && number > 0 {
				numbers[number] = struct{}{}
			}
		}
	}
	result := make([]int, 0, len(numbers))
	for number := range numbers {
		result = append(result, number)
	}
	sort.Ints(result)
	return result
}

func boundedRemoteHistory(
	current model.RemoteEvidence,
	previous threadstate.RemoteCache,
	previousFound bool,
	locals []gitscan.LocalLane,
	documents []memoryscan.Document,
) model.RemoteEvidence {
	observedPullRequests := make(map[int]struct{})
	observedIssues := make(map[int]struct{})
	if previousFound {
		for _, pullRequest := range previous.Evidence.PullRequests {
			observedPullRequests[pullRequest.Number] = struct{}{}
		}
		for _, issue := range previous.Evidence.Issues {
			observedIssues[issue.Number] = struct{}{}
		}
	}
	localBranches := make(map[string]struct{}, len(locals))
	for _, local := range locals {
		localBranches[local.Branch] = struct{}{}
	}
	anchoredIssueURLs := make(map[string]struct{})
	for _, document := range documents {
		if !document.Selected {
			continue
		}
		for _, issueURL := range document.IssueURLs {
			anchoredIssueURLs[issueURL] = struct{}{}
		}
	}
	pullRequests := make([]model.PullRequest, 0, len(current.PullRequests))
	for _, pullRequest := range current.PullRequests {
		_, observed := observedPullRequests[pullRequest.Number]
		_, local := localBranches[pullRequest.HeadRefName]
		anchored := false
		for _, issue := range pullRequest.ClosingIssues {
			if _, exists := anchoredIssueURLs[issue.URL]; exists {
				anchored = true
				break
			}
		}
		if strings.EqualFold(pullRequest.State, "OPEN") || observed || local || anchored {
			pullRequests = append(pullRequests, pullRequest)
		}
	}
	issues := make([]model.Issue, 0, len(current.Issues))
	for _, issue := range current.Issues {
		_, observed := observedIssues[issue.Number]
		_, anchored := anchoredIssueURLs[issue.URL]
		if strings.EqualFold(issue.State, "OPEN") || observed || anchored {
			issues = append(issues, issue)
		}
	}
	current.PullRequests = pullRequests
	current.Issues = issues
	return current
}

func emptyRemote() model.RemoteEvidence {
	return model.RemoteEvidence{
		PullRequests: []model.PullRequest{}, Issues: []model.Issue{},
		Errors: []model.ScanError{}, Warnings: []model.ScanError{},
	}
}

func selectedRepositories(configured, discovered []config.Repository) []config.Repository {
	repositories := make([]config.Repository, 0, len(configured)+len(discovered))
	seenGitHub := make(map[string]struct{}, len(configured)+len(discovered))
	for _, candidates := range [][]config.Repository{configured, discovered} {
		for _, repository := range candidates {
			if _, exists := seenGitHub[repository.GitHub]; exists {
				continue
			}
			seenGitHub[repository.GitHub] = struct{}{}
			repositories = append(repositories, repository)
		}
	}
	sort.Slice(repositories, func(i, j int) bool {
		if repositories[i].Path != repositories[j].Path {
			return repositories[i].Path < repositories[j].Path
		}
		return repositories[i].GitHub < repositories[j].GitHub
	})
	return repositories
}

func oldestRemoteObservation(state threadstate.State, repositories []config.Repository) *time.Time {
	var oldest time.Time
	for _, repository := range repositories {
		cached, found := state.Remote[repository.GitHub]
		if !found || cached.ObservedAt.IsZero() {
			return nil
		}
		if oldest.IsZero() || cached.ObservedAt.Before(oldest) {
			oldest = cached.ObservedAt
		}
	}
	if oldest.IsZero() {
		return nil
	}
	value := oldest
	return &value
}
