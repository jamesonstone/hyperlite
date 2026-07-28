package threadbuild

import (
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func activeFromEvidence(
	thread model.Thread,
	hasSpec bool,
	locals []gitscan.LocalLane,
	pullRequestHeadOIDs []string,
	staleAfter time.Duration,
	now time.Time,
) bool {
	if thread.Phase == model.ThreadComplete {
		return false
	}
	if hasOpenArtifact(thread) {
		return true
	}
	merged := hasMergedPullRequest(thread)
	if hasLiveLocal(locals, pullRequestHeadOIDs, merged, staleAfter, now) {
		return true
	}
	if thread.Phase == model.ThreadOperationalizing && hasOpenObligations(thread) {
		return true
	}
	return hasSpec && recent(thread.UpdatedAt, now, staleAfter)
}

func hasOpenArtifact(thread model.Thread) bool {
	for _, artifact := range thread.Artifacts {
		state := strings.ToLower(artifact.State)
		switch artifact.Kind {
		case model.ArtifactIssue:
			if state == "open" {
				return true
			}
		case model.ArtifactPullRequest:
			if state == "open" || state == "draft" {
				return true
			}
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
	locals []gitscan.LocalLane,
	pullRequestHeadOIDs []string,
	merged bool,
	staleAfter time.Duration,
	now time.Time,
) bool {
	for _, local := range locals {
		worktree := local.Worktree
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
				return recent(worktree.UpdatedAt, now, staleAfter)
			}
			continue
		}
		if local.Publication == model.PublicationNoUpstream ||
			local.Publication == model.PublicationUnknown {
			if recent(worktree.UpdatedAt, now, staleAfter) {
				return true
			}
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
