package cli

import (
	"context"
	"fmt"

	"github.com/jamesonstone/hyperlite/internal/worktreeprune"
	"github.com/spf13/cobra"
)

type staleWorktreePruner interface {
	Prune(context.Context, string, string) error
}

func (a App) pruneWorktreeCommand() *cobra.Command {
	return &cobra.Command{
		Use:    "prune-worktree <repository-path> <worktree-path>",
		Short:  "Prune verified stale worktree metadata",
		Args:   cobra.ExactArgs(2),
		Hidden: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := a.worktreePruner().Prune(cmd.Context(), args[0], args[1]); err != nil {
				return err
			}
			_, err := fmt.Fprintf(a.Out, "pruned stale worktree metadata: %s\n", args[1])
			return err
		},
	}
}

func (a App) worktreePruner() staleWorktreePruner {
	if a.worktreePrunerSource != nil {
		return a.worktreePrunerSource
	}
	return worktreeprune.Pruner{Runner: a.Runner}
}
