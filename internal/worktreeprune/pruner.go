package worktreeprune

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
)

type Pruner struct {
	Runner command.Runner
}

func (p Pruner) Prune(ctx context.Context, repositoryPath, worktreePath string) error {
	repositoryPath, err := config.CanonicalizePath(repositoryPath)
	if err != nil {
		return fmt.Errorf("resolve repository path: %w", err)
	}
	worktreePath, err = config.CanonicalizePath(worktreePath)
	if err != nil {
		return fmt.Errorf("resolve worktree path: %w", err)
	}
	if p.Runner == nil {
		return errors.New("worktree pruner has no command runner")
	}

	records, err := p.records(ctx, repositoryPath)
	if err != nil {
		return err
	}
	if !isPrunable(records, worktreePath) {
		return fmt.Errorf("worktree is no longer prunable: %s", worktreePath)
	}
	if _, err := p.Runner.Run(
		ctx, repositoryPath, "git", "worktree", "prune", "--dry-run", "--expire", "now", "--verbose",
	); err != nil {
		return fmt.Errorf("preview stale worktrees: %w", err)
	}
	if _, err := p.Runner.Run(
		ctx, repositoryPath, "git", "worktree", "prune", "--expire", "now", "--verbose",
	); err != nil {
		return fmt.Errorf("prune stale worktrees: %w", err)
	}
	records, err = p.records(ctx, repositoryPath)
	if err != nil {
		return fmt.Errorf("verify pruned worktree: %w", err)
	}
	if containsPath(records, worktreePath) {
		return fmt.Errorf("worktree metadata remains after prune: %s", worktreePath)
	}
	return nil
}

func (p Pruner) records(ctx context.Context, repositoryPath string) ([]record, error) {
	output, err := p.Runner.Run(
		ctx, repositoryPath, "git", "worktree", "list", "--porcelain", "-z",
	)
	if err != nil {
		return nil, fmt.Errorf("list worktrees: %w", err)
	}
	return parseRecords(output), nil
}

type record struct {
	path     string
	prunable bool
}

func parseRecords(output []byte) []record {
	var records []record
	var current record
	flush := func() {
		if current.path != "" {
			records = append(records, current)
			current = record{}
		}
	}
	for _, item := range bytes.Split(output, []byte{0}) {
		line := string(item)
		if line == "" {
			flush()
			continue
		}
		key, value, _ := strings.Cut(line, " ")
		switch key {
		case "worktree":
			if current.path != "" {
				flush()
			}
			current.path = filepath.Clean(value)
		case "prunable":
			current.prunable = true
		}
	}
	flush()
	return records
}

func isPrunable(records []record, path string) bool {
	path = filepath.Clean(path)
	for _, record := range records {
		if record.path == path {
			return record.prunable
		}
	}
	return false
}

func containsPath(records []record, path string) bool {
	path = filepath.Clean(path)
	for _, record := range records {
		if record.path == path {
			return true
		}
	}
	return false
}
