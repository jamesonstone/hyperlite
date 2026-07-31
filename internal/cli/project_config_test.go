package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestConfiguredProjectMutationCommandsPreserveConfiguration(t *testing.T) {
	root := t.TempDir()
	first := testRepository(t, root, "first")
	second := testRepository(t, root, "second")
	configPath := filepath.Join(root, "config.yaml")
	initial := config.Config{
		Version:  config.Version,
		Projects: []config.Source{{Path: first}},
		Sources:  []config.Source{{Path: root}},
		Repositories: []config.Repository{{
			Name: "first", Path: first, GitHub: "owner/first", Base: "trunk", Remote: "upstream",
		}},
	}
	if err := (config.AtomicWriter{}).Write(configPath, initial); err != nil {
		t.Fatal(err)
	}

	var output strings.Builder
	add := App{Out: &output}.Root()
	add.SetArgs([]string{"--config", configPath, "projects", "add", second})
	if err := add.ExecuteContext(t.Context()); err != nil {
		t.Fatal(err)
	}
	if output.String() != "added project: "+second+"\n" {
		t.Fatalf("add output = %q", output.String())
	}
	loaded := loadTestConfig(t, configPath)
	if len(loaded.Projects) != 2 || loaded.Projects[0].Path != first || loaded.Projects[1].Path != second {
		t.Fatalf("projects after add = %#v", loaded.Projects)
	}
	if len(loaded.Sources) != 1 || len(loaded.Repositories) != 1 ||
		loaded.Repositories[0].Base != "trunk" || loaded.Repositories[0].Remote != "upstream" {
		t.Fatalf("configuration inventory changed = %#v", loaded)
	}

	output.Reset()
	remove := App{Out: &output}.Root()
	remove.SetArgs([]string{"--config", configPath, "projects", "remove", first})
	if err := remove.ExecuteContext(t.Context()); err != nil {
		t.Fatal(err)
	}
	if output.String() != "removed project: "+first+"\n" {
		t.Fatalf("remove output = %q", output.String())
	}
	loaded = loadTestConfig(t, configPath)
	if len(loaded.Projects) != 1 || loaded.Projects[0].Path != second {
		t.Fatalf("projects after remove = %#v", loaded.Projects)
	}

	output.Reset()
	removeAgain := App{Out: &output}.Root()
	removeAgain.SetArgs([]string{"--config", configPath, "projects", "remove", first})
	if err := removeAgain.ExecuteContext(t.Context()); err != nil {
		t.Fatal(err)
	}
	if output.String() != "project not configured: "+first+"\n" {
		t.Fatalf("idempotent remove output = %q", output.String())
	}
}

func TestConfiguredProjectMutationCommandsAreIdempotentAndRejectNonRepositories(t *testing.T) {
	root := t.TempDir()
	project := testRepository(t, root, "project")
	ordinaryDirectory := filepath.Join(root, "ordinary")
	if err := os.Mkdir(ordinaryDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(root, "config.yaml")
	if err := (config.AtomicWriter{}).Write(configPath, config.Config{
		Version: config.Version, Projects: []config.Source{{Path: project}},
	}); err != nil {
		t.Fatal(err)
	}

	var output strings.Builder
	add := App{Out: &output}.Root()
	add.SetArgs([]string{"--config", configPath, "projects", "add", project})
	if err := add.ExecuteContext(t.Context()); err != nil {
		t.Fatal(err)
	}
	if output.String() != "project already configured: "+project+"\n" {
		t.Fatalf("idempotent add output = %q", output.String())
	}

	reject := App{Out: &output}.Root()
	reject.SetArgs([]string{"--config", configPath, "projects", "add", ordinaryDirectory})
	err := reject.ExecuteContext(t.Context())
	if err == nil || !strings.Contains(err.Error(), "not a Git repository root") {
		t.Fatalf("invalid repository error = %v", err)
	}
	if projects := loadTestConfig(t, configPath).Projects; len(projects) != 1 || projects[0].Path != project {
		t.Fatalf("invalid add changed projects = %#v", projects)
	}
}

func testRepository(t *testing.T, root, name string) string {
	t.Helper()
	path := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Join(path, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	canonical, err := config.CanonicalizeSourcePath(path)
	if err != nil {
		t.Fatal(err)
	}
	return canonical
}

func loadTestConfig(t *testing.T, path string) config.Config {
	t.Helper()
	loaded, err := config.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	return loaded
}
