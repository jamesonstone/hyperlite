package workscan

import (
	"path/filepath"
	"sort"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/memoryscan"
)

func (s Scanner) scanRepositoryMemory(
	repository config.Repository,
	locals []gitscan.LocalLane,
) memoryscan.Result {
	roots := []string{repository.Path}
	seenRoots := map[string]struct{}{repository.Path: {}}
	for _, local := range locals {
		path := strings.TrimSpace(local.Worktree.Path)
		if path == "" || local.Worktree.Prunable ||
			(local.Worktree.Detached && !isIssueWorktreePath(path)) {
			continue
		}
		if _, exists := seenRoots[path]; exists {
			continue
		}
		seenRoots[path] = struct{}{}
		roots = append(roots, path)
	}
	byID := make(map[string]memoryscan.Document)
	var diagnostics []memoryscan.Diagnostic
	for _, root := range roots {
		result := s.Memory.Scan(root)
		diagnostics = append(diagnostics, result.Diagnostics...)
		for _, document := range result.Documents {
			byID[document.ID] = document
		}
	}
	documents := make([]memoryscan.Document, 0, len(byID))
	for _, document := range byID {
		documents = append(documents, document)
	}
	sort.Slice(documents, func(i, j int) bool { return documents[i].ID < documents[j].ID })
	return memoryscan.Result{Documents: documents, Diagnostics: diagnostics}
}

func isIssueWorktreePath(path string) bool {
	return gitscan.IssueNumber(filepath.Base(filepath.Clean(path))) > 0
}
