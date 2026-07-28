package threadbuild

import (
	"path/filepath"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func activeFromEvidence(
	thread model.Thread,
	repository config.Repository,
	hasSpec bool,
	locals []gitscan.LocalLane,
	pullRequestHeadOIDs []string,
	staleAfter time.Duration,
	now time.Time,
) bool {
	if thread.Phase == model.ThreadComplete {
		return false
	}
	if hasOpenPullRequest(thread) {
		return true
	}
	merged := hasMergedPullRequest(thread)
	if hasLiveLocal(repository, locals, pullRequestHeadOIDs, merged, staleAfter, now) {
		return true
	}
	if merged && hasOpenObligations(thread) {
		return true
	}
	if hasRecentOpenIssue(thread, staleAfter, now) {
		return true
	}
	if hasTerminalArtifact(thread) {
		return false
	}
	return hasSpec && hasRecentSpec(thread, staleAfter, now)
}

func hasOpenPullRequest(thread model.Thread) bool {
	for _, artifact := range thread.Artifacts {
		state := strings.ToLower(artifact.State)
		if artifact.Kind == model.ArtifactPullRequest &&
			(state == "open" || state == "draft") {
			return true
		}
	}
	return false
}

func hasMergedPullRequest(thread model.Thread) bool {
	for _, artifact := range thread.Artifacts {
		if artifact.Kind == model.ArtifactPullRequest &&
			strings.EqualFold(artifact.State, "merged") {
			return true
		}
	}
	return false
}

func hasLiveLocal(
	repository config.Repository,
	locals []gitscan.LocalLane,
	pullRequestHeadOIDs []string,
	merged bool,
	staleAfter time.Duration,
	now time.Time,
) bool {
	for _, local := range locals {
		worktree := local.Worktree
		if !durableLocal(repository, local) ||
			!recent(worktree.UpdatedAt, now, staleAfter) {
			continue
		}
		if worktree.Conflicted > 0 ||
			worktree.Staged+worktree.Unstaged+worktree.Untracked > 0 ||
			worktree.Ahead > 0 ||
			local.Publication == model.PublicationUnpushed ||
			local.Publication == model.PublicationDiverged {
			return true
		}
		if merged {
			if len(pullRequestHeadOIDs) > 0 &&
				worktree.HeadOID != "" &&
				!containsString(pullRequestHeadOIDs, worktree.HeadOID) {
				return true
			}
			continue
		}
		if local.Publication == model.PublicationNoUpstream ||
			local.Publication == model.PublicationUnknown {
			return true
		}
	}
	return false
}

func durableLocal(repository config.Repository, local gitscan.LocalLane) bool {
	branch := gitscan.IdentityBranch(local)
	if branch == "" || branch == repository.Base ||
		local.Publication == model.PublicationBase {
		return false
	}
	path := filepath.Clean(local.Worktree.Path)
	if path == filepath.Clean(repository.Path) {
		return true
	}
	return strings.EqualFold(filepath.Base(path), branch)
}

func hasRecentOpenIssue(thread model.Thread, staleAfter time.Duration, now time.Time) bool {
	for _, artifact := range thread.Artifacts {
		if artifact.Kind == model.ArtifactIssue &&
			strings.EqualFold(artifact.State, "open") &&
			recent(artifact.UpdatedAt, now, staleAfter) {
			return true
		}
	}
	return false
}

func hasTerminalArtifact(thread model.Thread) bool {
	for _, artifact := range thread.Artifacts {
		if artifact.Kind == model.ArtifactPullRequest &&
			strings.EqualFold(artifact.State, "merged") {
			return true
		}
		if artifact.Kind == model.ArtifactIssue &&
			strings.EqualFold(artifact.State, "closed") {
			return true
		}
	}
	return false
}

func hasRecentSpec(thread model.Thread, staleAfter time.Duration, now time.Time) bool {
	for _, artifact := range thread.Artifacts {
		if artifact.Kind == model.ArtifactSpec &&
			recent(artifact.UpdatedAt, now, staleAfter) {
			return true
		}
	}
	return false
}

func containsString(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
