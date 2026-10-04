package cli

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestConfiguredProjectListJSON(t *testing.T) {
	repository, configPath := testDiscoveredProject(t)
	var output strings.Builder
	app := App{Out: &output, Runner: command.ExecRunner{}}
	root := app.Root()
	root.SetArgs([]string{"--config", configPath, "projects", "list", "--json"})
	if err := root.ExecuteContext(t.Context()); err != nil {
		t.Fatal(err)
	}
	var list projectList
	if err := json.Unmarshal([]byte(output.String()), &list); err != nil {
		t.Fatalf("decode %q: %v", output.String(), err)
	}
	if len(list.Projects) != 1 || list.Projects[0].Name != "kit" ||
		list.Projects[0].Path != repository || list.Projects[0].Base != "main" {
		t.Fatalf("list = %#v", list)
	}
}

func testDiscoveredProject(t *testing.T) (repository, configPath string) {
	t.Helper()
	root := t.TempDir()
	repository = filepath.Join(root, "kit")
	if err := os.MkdirAll(repository, 0o755); err != nil {
		t.Fatal(err)
	}
	runTestGit(t, repository, "init", "-b", "main")
	runTestGit(t, repository, "config", "user.name", "Hyperlite Test")
	runTestGit(t, repository, "config", "user.email", "hyperlite@example.com")
	if err := os.WriteFile(filepath.Join(repository, "README.md"), []byte("test\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runTestGit(t, repository, "add", "README.md")
	runTestGit(t, repository, "commit", "-m", "initial")
	runTestGit(t, repository, "remote", "add", "origin", "https://github.com/owner/kit.git")
	runTestGit(t, repository, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
	canonical, err := config.CanonicalizeSourcePath(repository)
	if err != nil {
		t.Fatal(err)
	}
	configPath = filepath.Join(root, "config.yaml")
	if err := (config.AtomicWriter{}).Write(configPath, config.Config{
		Version:  config.Version,
		Projects: []config.Source{{Path: canonical}},
	}); err != nil {
		t.Fatal(err)
	}
	return canonical, configPath
}

func runTestGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	command := exec.Command("git", args...)
	command.Dir = dir
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v: %s", args, err, output)
	}
}
