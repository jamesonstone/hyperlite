package cli

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func initRepository(t *testing.T, path string) {
	t.Helper()
	if output, err := exec.Command("git", "init", "-q", path).CombinedOutput(); err != nil {
		t.Fatalf("git init %s: %v %s", path, err, output)
	}
}

func TestRefreshWatchesNewSourceRepositoriesButNotExclusionsOrWorktrees(t *testing.T) {
	source, _ := filepath.EvalSymlinks(t.TempDir())
	existing := filepath.Join(source, "existing")
	removed := filepath.Join(source, "removed")
	fresh := filepath.Join(source, "fresh")
	for _, repo := range []string{existing, removed, fresh} {
		initRepository(t, repo)
	}
	worktreeHolder := filepath.Join(source, "worktrees", "linked")
	if err := os.MkdirAll(worktreeHolder, 0o755); err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(worktreeHolder, ".git"), []byte("gitdir: "+existing+"/.git/worktrees/linked\n"), 0o600)

	configPath := filepath.Join(t.TempDir(), "config.yaml")
	contents := "version: 2\nprojects:\n  - path: " + existing + "\n  - path: " + removed + "\nsources:\n  - path: " + source + "\n"
	if err := os.WriteFile(configPath, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	// Removing a project under a source records an exclusion.
	if err := config.Mutate(configPath, func(cfg *config.Config) (bool, error) {
		updated, err := config.ReplaceProjectPaths(*cfg, []string{existing})
		*cfg = updated
		return true, err
	}); err != nil {
		t.Fatal(err)
	}
	scanner := &recordingProjectPullRequestScanner{result: model.ProjectPullRequestScan{
		Projects: []model.ProjectPullRequests{}, Errors: []model.ScanError{}, Warnings: []model.ScanError{},
	}}
	var output bytes.Buffer
	app := App{Out: &output, pullRequestScannerSource: scanner}
	if err := app.runPullRequests(t.Context(), configPath, pullRequestOptions{jsonOutput: true}); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(configPath)
	if err != nil {
		t.Fatal(err)
	}
	var paths []string
	for _, project := range cfg.Projects {
		paths = append(paths, project.Path)
	}
	if strings.Join(paths, ",") != existing+","+fresh {
		t.Fatalf("projects = %v, want existing and fresh only", paths)
	}
	if len(cfg.ExcludedProjects) != 1 || cfg.ExcludedProjects[0] != removed {
		t.Fatalf("excluded = %v", cfg.ExcludedProjects)
	}
	if !strings.Contains(output.String(), "project-added") || !strings.Contains(output.String(), fresh) {
		t.Fatalf("output = %s", output.String())
	}
	// Adding a removed project back clears its exclusion.
	if err := config.Mutate(configPath, func(cfg *config.Config) (bool, error) {
		updated, err := config.ReplaceProjectPaths(*cfg, []string{existing, fresh, removed})
		*cfg = updated
		return true, err
	}); err != nil {
		t.Fatal(err)
	}
	if cfg, _ = config.Load(configPath); len(cfg.ExcludedProjects) != 0 {
		t.Fatalf("excluded after re-add = %v", cfg.ExcludedProjects)
	}
}
