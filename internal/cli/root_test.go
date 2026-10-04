package cli

import (
	"strings"
	"testing"
)

func TestResolveColor(t *testing.T) {
	t.Run("auto uses terminal output", func(t *testing.T) {
		t.Setenv("NO_COLOR", "")
		app := App{OutputIsTTY: func() bool { return true }}
		color, err := app.resolveColor("auto")
		if err != nil || !color {
			t.Fatalf("color, err = %t, %v", color, err)
		}
	})

	t.Run("NO_COLOR disables automatic color", func(t *testing.T) {
		t.Setenv("NO_COLOR", "1")
		app := App{OutputIsTTY: func() bool { return true }}
		color, err := app.resolveColor("auto")
		if err != nil || color {
			t.Fatalf("color, err = %t, %v", color, err)
		}
	})

	t.Run("always overrides non terminal output", func(t *testing.T) {
		app := App{OutputIsTTY: func() bool { return false }}
		color, err := app.resolveColor("always")
		if err != nil || !color {
			t.Fatalf("color, err = %t, %v", color, err)
		}
	})

	t.Run("never disables color", func(t *testing.T) {
		app := App{OutputIsTTY: func() bool { return true }}
		color, err := app.resolveColor("never")
		if err != nil || color {
			t.Fatalf("color, err = %t, %v", color, err)
		}
	})
}

func TestRootDoesNotExposeWorktreePruning(t *testing.T) {
	for _, command := range (App{}).Root().Commands() {
		if command.Name() == "prune-worktree" {
			t.Fatal("worktree pruning command should be removed")
		}
	}
}

func TestRootWithoutSubcommandPrintsHelp(t *testing.T) {
	var output strings.Builder
	root := (App{Out: &output}).Root()
	root.SetOut(&output)
	root.SetArgs(nil)
	if err := root.Execute(); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"pull-requests", "projects", "version"} {
		if !strings.Contains(output.String(), want) {
			t.Fatalf("help output missing %q: %q", want, output.String())
		}
	}
	for _, removed := range []string{"scan", "infer", "thread", "notepad", "pinboard", "agent"} {
		for _, command := range root.Commands() {
			if command.Name() == removed {
				t.Fatalf("retired command %q is still registered", removed)
			}
		}
	}
}
