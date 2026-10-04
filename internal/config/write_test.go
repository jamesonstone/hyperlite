package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestAtomicWriterWritesLoadableVersionTwoConfig(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "nested", "config.yaml")
	cfg := Config{
		Version: Version1,
		Settings: Settings{
			ScanInterval: time.Minute, RemoteRefreshInterval: 5 * time.Minute,
			StaleAfter: 24 * time.Hour, MaxParallel: 4, GitHubAuthor: "@me", GitHubScope: GitHubScopeMine,
			OllamaModel: "gpt-oss:20b",
		},
		Sources: []Source{{Path: root}},
	}
	if err := (AtomicWriter{}).Write(path, cfg); err != nil {
		t.Fatal(err)
	}
	loaded, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Version != Version || len(loaded.Sources) != 1 || loaded.Settings.OllamaModel != "gpt-oss:20b" {
		t.Fatalf("loaded = %#v", loaded)
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(contents), "version: 2\n") {
		t.Fatalf("contents = %s", contents)
	}
}

func TestMarshalRejectsInvalidOllamaModelBeforeWriting(t *testing.T) {
	_, err := Marshal(Config{
		Settings: Settings{OllamaModel: "bad\nmodel"},
		Sources:  []Source{{Path: t.TempDir()}},
	})
	if err == nil || !strings.Contains(err.Error(), "ollama_model") {
		t.Fatalf("error = %v", err)
	}
}

func TestReplaceProjectPathsUpdatesOnlyHyperliteSelection(t *testing.T) {
	root := t.TempDir()
	first := filepath.Join(root, "first")
	second := filepath.Join(root, "second")
	if err := os.MkdirAll(first, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(second, 0o755); err != nil {
		t.Fatal(err)
	}
	current := Config{
		Version: Version,
		Sources: []Source{{Path: root}},
		Repositories: []Repository{{
			Name: "first", Path: first, GitHub: "owner/first", Base: "trunk", Remote: "upstream",
		}},
	}
	replaced, err := ReplaceProjectPaths(current, []string{second, first, second})
	if err != nil {
		t.Fatal(err)
	}
	canonicalSecond, err := filepath.EvalSymlinks(second)
	if err != nil {
		t.Fatal(err)
	}
	canonicalFirst, err := filepath.EvalSymlinks(first)
	if err != nil {
		t.Fatal(err)
	}
	if len(replaced.Repositories) != 1 || replaced.Repositories[0].Base != "trunk" ||
		len(replaced.Sources) != 1 || replaced.Sources[0].Path != root {
		t.Fatalf("legacy inventory = %#v %#v", replaced.Sources, replaced.Repositories)
	}
	if len(replaced.Projects) != 2 ||
		replaced.Projects[0].Path != canonicalFirst ||
		replaced.Projects[1].Path != canonicalSecond {
		t.Fatalf("projects = %#v", replaced.Projects)
	}
}
