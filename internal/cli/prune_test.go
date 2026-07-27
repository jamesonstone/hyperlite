package cli

import (
	"context"
	"strings"
	"testing"
)

func TestPruneWorktreeCommandUsesInjectedPruner(t *testing.T) {
	var output strings.Builder
	pruner := &recordingPruner{}
	app := App{Out: &output, worktreePrunerSource: pruner}
	command := app.Root()
	command.SetArgs([]string{"prune-worktree", "/repo", "/stale"})
	if err := command.ExecuteContext(t.Context()); err != nil {
		t.Fatal(err)
	}
	if pruner.repositoryPath != "/repo" || pruner.worktreePath != "/stale" {
		t.Fatalf("pruner = %#v", pruner)
	}
	if output.String() != "pruned stale worktree metadata: /stale\n" {
		t.Fatalf("output = %q", output.String())
	}
}

type recordingPruner struct {
	repositoryPath string
	worktreePath   string
}

func (p *recordingPruner) Prune(_ context.Context, repositoryPath, worktreePath string) error {
	p.repositoryPath = repositoryPath
	p.worktreePath = worktreePath
	return nil
}
