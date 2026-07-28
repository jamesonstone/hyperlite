package workscan

import (
	"net/url"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/memoryscan"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func (s Scanner) scanRepositoryMemory(
	repository config.Repository,
	locals []gitscan.LocalLane,
	staleAfter time.Duration,
	now time.Time,
) memoryscan.Result {
	type memoryRoot struct {
		path        string
		issueNumber int
	}
	roots := []memoryRoot{{path: repository.Path}}
	seenRoots := map[string]struct{}{repository.Path: {}}
	for _, local := range locals {
		path := strings.TrimSpace(local.Worktree.Path)
		if !currentMemoryLane(repository, local, staleAfter, now) {
			continue
		}
		if _, exists := seenRoots[path]; exists {
			continue
		}
		seenRoots[path] = struct{}{}
		roots = append(roots, memoryRoot{
			path: path, issueNumber: gitscan.IssueNumber(gitscan.IdentityBranch(local)),
		})
	}
	byIdentity := make(map[string]memoryscan.Document)
	var diagnostics []memoryscan.Diagnostic
	for _, root := range roots {
		result := s.Memory.Scan(root.path)
		diagnostics = append(diagnostics, result.Diagnostics...)
		for _, document := range result.Documents {
			if root.issueNumber > 0 &&
				!documentAnchorsIssue(document, repository.GitHub, root.issueNumber) {
				continue
			}
			key := documentIdentity(document)
			current, exists := byIdentity[key]
			if !exists || document.UpdatedAt.After(current.UpdatedAt) ||
				(document.UpdatedAt.Equal(current.UpdatedAt) &&
					document.RepositoryRoot < current.RepositoryRoot) {
				byIdentity[key] = document
			}
		}
	}
	documents := make([]memoryscan.Document, 0, len(byIdentity))
	for _, document := range byIdentity {
		documents = append(documents, document)
	}
	sort.Slice(documents, func(i, j int) bool {
		if documents[i].FeatureID != documents[j].FeatureID {
			return documents[i].FeatureID < documents[j].FeatureID
		}
		if documents[i].Slug != documents[j].Slug {
			return documents[i].Slug < documents[j].Slug
		}
		return documents[i].Path < documents[j].Path
	})
	return memoryscan.Result{Documents: documents, Diagnostics: diagnostics}
}

func documentAnchorsIssue(
	document memoryscan.Document,
	repository string,
	issueNumber int,
) bool {
	for _, number := range document.IssueNumbers {
		if number == issueNumber {
			return true
		}
	}
	for _, rawURL := range document.IssueURLs {
		parsed, err := url.Parse(rawURL)
		if err != nil || !strings.EqualFold(parsed.Host, "github.com") {
			continue
		}
		parts := strings.Split(strings.Trim(parsed.Path, "/"), "/")
		if len(parts) != 4 || parts[2] != "issues" ||
			!strings.EqualFold(parts[0]+"/"+parts[1], repository) {
			continue
		}
		number, numberErr := strconv.Atoi(parts[len(parts)-1])
		if numberErr == nil && number == issueNumber {
			return true
		}
	}
	return false
}

func currentMemoryLane(
	repository config.Repository,
	local gitscan.LocalLane,
	staleAfter time.Duration,
	now time.Time,
) bool {
	path := strings.TrimSpace(local.Worktree.Path)
	if path == "" || filepath.Clean(path) == filepath.Clean(repository.Path) ||
		local.Worktree.Prunable {
		return false
	}
	branch := gitscan.IdentityBranch(local)
	if gitscan.IssueNumber(branch) == 0 ||
		!strings.EqualFold(filepath.Base(filepath.Clean(path)), branch) {
		return false
	}
	if staleAfter <= 0 {
		staleAfter = 24 * time.Hour
	}
	if local.Worktree.UpdatedAt.IsZero() || local.Worktree.UpdatedAt.After(now) ||
		now.Sub(local.Worktree.UpdatedAt) > staleAfter {
		return false
	}
	worktree := local.Worktree
	return worktree.Conflicted > 0 ||
		worktree.Staged+worktree.Unstaged+worktree.Untracked > 0 ||
		worktree.Ahead > 0 || worktree.AheadBase > 0 ||
		local.Publication == model.PublicationNoUpstream ||
		local.Publication == model.PublicationUnpushed ||
		local.Publication == model.PublicationDiverged
}

func documentIdentity(document memoryscan.Document) string {
	var anchors []string
	for _, number := range document.IssueNumbers {
		anchors = append(anchors, strconv.Itoa(number))
	}
	anchors = append(anchors, document.IssueURLs...)
	sort.Strings(anchors)
	return strings.Join([]string{
		document.FeatureID, document.Slug, document.Path, strings.Join(anchors, "\x01"),
	}, "\x00")
}
