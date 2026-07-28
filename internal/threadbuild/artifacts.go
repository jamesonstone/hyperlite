package threadbuild

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func addIssue(repo config.Repository, issue model.Issue, stale bool, builders map[string]*accumulator, aliases map[string]string, now time.Time) {
	id := issueID(repo.GitHub, issue.Number)
	builder := builderForAlias(id, builders, aliases)
	if builder == nil && !strings.EqualFold(issue.State, "OPEN") && !recent(issue.UpdatedAt, now, 30*24*time.Hour) {
		return
	}
	if builder == nil {
		builder = ensure(builders, id, repo)
	}
	builder.issueNumber = issue.Number
	addAliases(builder, aliases, builder.thread.ID, id, issue.URL)
	if builder.thread.Title == "" {
		builder.thread.Title = issue.Title
	}
	if builder.thread.Goal == "" {
		builder.thread.Goal = firstParagraph(issue.Body)
	}
	evidenceID := fmt.Sprintf("issue:%s#%d", repo.GitHub, issue.Number)
	freshness := freshness(stale)
	addEvidence(&builder.thread, model.EvidenceRef{
		ID: evidenceID, Source: "github", Repository: repo.GitHub, Kind: "issue",
		Title: issue.Title, URL: issue.URL, Excerpt: bounded(issue.Body),
		UpdatedAt: issue.UpdatedAt, Freshness: freshness,
	})
	addArtifact(&builder.thread, model.ThreadArtifact{
		ID: evidenceID, Kind: model.ArtifactIssue, Repository: repo.GitHub,
		Title: issue.Title, State: strings.ToLower(issue.State), URL: issue.URL,
		EvidenceID: evidenceID, UpdatedAt: issue.UpdatedAt, Freshness: freshness,
	})
}

func addPullRequest(repo config.Repository, pullRequest model.PullRequest, stale bool, builders map[string]*accumulator, aliases map[string]string, now time.Time) {
	builder := matchPullRequest(repo, pullRequest, builders, aliases)
	if builder == nil && !strings.EqualFold(pullRequest.State, "OPEN") &&
		!recent(pullRequest.UpdatedAt, now, 30*24*time.Hour) {
		return
	}
	id := fmt.Sprintf("pr:%s#%d", repo.GitHub, pullRequest.Number)
	if builder == nil {
		builder = ensure(builders, id, repo)
	}
	if pullRequest.HeadRefOID != "" {
		builder.headOIDs = append(builder.headOIDs, pullRequest.HeadRefOID)
	}
	addAliases(builder, aliases, builder.thread.ID, id, pullRequest.URL, branchAlias(repo.GitHub, pullRequest.HeadRefName))
	if builder.thread.Title == "" {
		builder.thread.Title = pullRequest.Title
	}
	if builder.thread.Goal == "" {
		builder.thread.Goal = firstParagraph(pullRequest.Body)
	}
	freshness := freshness(stale)
	evidenceID := id
	addEvidence(&builder.thread, model.EvidenceRef{
		ID: evidenceID, Source: "github", Repository: repo.GitHub, Kind: "pull_request",
		Title: pullRequest.Title, URL: pullRequest.URL, Excerpt: bounded(pullRequest.Body),
		UpdatedAt: pullRequest.UpdatedAt, Freshness: freshness,
	})
	state := strings.ToLower(pullRequest.State)
	if !pullRequest.MergedAt.IsZero() {
		state = "merged"
	}
	if pullRequest.IsDraft && state == "open" {
		state = "draft"
	}
	addArtifact(&builder.thread, model.ThreadArtifact{
		ID: evidenceID, Kind: model.ArtifactPullRequest, Repository: repo.GitHub,
		Title: pullRequest.Title, State: state, URL: pullRequest.URL,
		EvidenceID: evidenceID, UpdatedAt: pullRequest.UpdatedAt, Freshness: freshness,
	})
	for _, reviewThread := range pullRequest.Feedback.Threads {
		if len(reviewThread.Comments) == 0 {
			continue
		}
		last := reviewThread.Comments[len(reviewThread.Comments)-1]
		reviewID := "review:" + reviewThread.ID
		addEvidence(&builder.thread, model.EvidenceRef{
			ID: reviewID, Source: "github", Repository: repo.GitHub, Kind: "review",
			Title: "Review on " + reviewThread.Path, URL: last.URL,
			Excerpt: bounded(last.Body), UpdatedAt: last.UpdatedAt, Freshness: freshness,
		})
		addArtifact(&builder.thread, model.ThreadArtifact{
			ID: reviewID, Kind: model.ArtifactReview, Repository: repo.GitHub,
			Title: "Unresolved review on " + reviewThread.Path, State: "unresolved",
			URL: last.URL, Path: reviewThread.Path, EvidenceID: reviewID,
			UpdatedAt: last.UpdatedAt, Freshness: freshness,
		})
	}
}

func matchPullRequest(repo config.Repository, pullRequest model.PullRequest, builders map[string]*accumulator, aliases map[string]string) *accumulator {
	for _, issue := range pullRequest.ClosingIssues {
		if builder := builderForAlias(issueID(repo.GitHub, issue.Number), builders, aliases); builder != nil {
			return builder
		}
	}
	if builder := builderForAlias(branchAlias(repo.GitHub, pullRequest.HeadRefName), builders, aliases); builder != nil {
		return builder
	}
	if number := branchIssueNumber(pullRequest.HeadRefName); number > 0 {
		if builder := builderForAlias(issueID(repo.GitHub, number), builders, aliases); builder != nil {
			return builder
		}
		return ensure(builders, issueID(repo.GitHub, number), repo)
	}
	return nil
}

func addLocal(repo config.Repository, local gitscan.LocalLane, builders map[string]*accumulator, aliases map[string]string, now time.Time) {
	if !materialLocal(local) {
		return
	}
	branch := localIdentityBranch(local)
	alias := branchAlias(repo.GitHub, branch)
	builder := builderForAlias(alias, builders, aliases)
	if builder == nil && local.Worktree.Detached && local.Worktree.HeadOID != "" {
		builder = builderForHeadOID(local.Worktree.HeadOID, builders)
	}
	if builder == nil {
		id := alias
		if number := branchIssueNumber(branch); number > 0 {
			id = issueID(repo.GitHub, number)
		}
		builder = ensure(builders, id, repo)
	}
	addAliases(builder, aliases, builder.thread.ID, alias)
	if builder.thread.Title == "" {
		builder.thread.Title = branch
	}
	if builder.thread.Goal == "" {
		builder.thread.Goal = "Continue material work on " + branch
	}
	evidenceID := fmt.Sprintf("git:%s@%s", repo.GitHub, branch)
	summary := fmt.Sprintf(
		"%d staged, %d unstaged, %d untracked, %d conflicted; %d commit(s) ahead of base",
		local.Worktree.Staged, local.Worktree.Unstaged, local.Worktree.Untracked,
		local.Worktree.Conflicted, local.Worktree.AheadBase,
	)
	addEvidence(&builder.thread, model.EvidenceRef{
		ID: evidenceID, Source: "git", Repository: repo.GitHub, Kind: "worktree",
		Title: branch, Path: local.Worktree.Path, Excerpt: summary,
		UpdatedAt: local.Worktree.UpdatedAt, Freshness: "current",
	})
	addArtifact(&builder.thread, model.ThreadArtifact{
		ID: evidenceID, Kind: model.ArtifactWorktree, Repository: repo.GitHub,
		Title: branch, State: localState(local), Path: local.Worktree.Path,
		EvidenceID: evidenceID, UpdatedAt: local.Worktree.UpdatedAt, Freshness: "current",
	})
	if local.Worktree.UpdatedAt.IsZero() {
		builder.thread.UpdatedAt = now
	}
}

func localIdentityBranch(local gitscan.LocalLane) string {
	if local.Worktree.Detached {
		name := filepath.Base(filepath.Clean(local.Worktree.Path))
		if branchIssueNumber(name) > 0 {
			return name
		}
	}
	return local.Branch
}

func materialLocal(local gitscan.LocalLane) bool {
	worktree := local.Worktree
	if worktree.Prunable {
		return false
	}
	return worktree.Conflicted > 0 ||
		worktree.Staged+worktree.Unstaged+worktree.Untracked > 0 ||
		worktree.Ahead > 0 || worktree.AheadBase > 0 ||
		local.Publication == model.PublicationNoUpstream ||
		local.Publication == model.PublicationUnpushed ||
		local.Publication == model.PublicationDiverged
}

func builderForHeadOID(headOID string, builders map[string]*accumulator) *accumulator {
	for _, builder := range builders {
		for _, value := range builder.headOIDs {
			if value == headOID {
				return builder
			}
		}
	}
	return nil
}

func localState(local gitscan.LocalLane) string {
	switch {
	case local.Worktree.Conflicted > 0:
		return "conflicted"
	case local.Worktree.Staged+local.Worktree.Unstaged+local.Worktree.Untracked > 0:
		return "dirty"
	case local.Worktree.Ahead > 0 || local.Worktree.AheadBase > 0:
		return "ahead"
	default:
		return string(local.Publication)
	}
}

func builderForAlias(alias string, builders map[string]*accumulator, aliases map[string]string) *accumulator {
	if id, exists := aliases[alias]; exists {
		return builders[id]
	}
	return builders[alias]
}

func addEvidence(thread *model.Thread, evidence model.EvidenceRef) {
	for index := range thread.Evidence {
		if thread.Evidence[index].ID == evidence.ID {
			thread.Evidence[index] = evidence
			return
		}
	}
	thread.Evidence = append(thread.Evidence, evidence)
	if evidence.UpdatedAt.After(thread.UpdatedAt) {
		thread.UpdatedAt = evidence.UpdatedAt
	}
}

func addArtifact(thread *model.Thread, artifact model.ThreadArtifact) {
	for index := range thread.Artifacts {
		if thread.Artifacts[index].ID == artifact.ID {
			thread.Artifacts[index] = artifact
			return
		}
	}
	thread.Artifacts = append(thread.Artifacts, artifact)
}

func freshness(stale bool) string {
	if stale {
		return "stale"
	}
	return "current"
}

func branchAlias(repository, branch string) string {
	return fmt.Sprintf("branch:%s@%s", repository, branch)
}

func branchIssueNumber(branch string) int {
	var number int
	if _, err := fmt.Sscanf(strings.ToUpper(branch), "GH-%d", &number); err != nil {
		return 0
	}
	return number
}

func uniqueArtifacts(values []model.ThreadArtifact) []model.ThreadArtifact {
	sort.Slice(values, func(i, j int) bool {
		if values[i].Kind != values[j].Kind {
			return values[i].Kind < values[j].Kind
		}
		return values[i].ID < values[j].ID
	})
	return values
}
