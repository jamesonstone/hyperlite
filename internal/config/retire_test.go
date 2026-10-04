package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func writeProjectsConfig(t *testing.T, paths ...string) string {
	t.Helper()
	contents := "version: 2\nprojects:\n"
	for _, path := range paths {
		contents += "  - path: " + path + "\n"
	}
	configPath := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(configPath, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	return configPath
}

func TestMissingProjectDirectoryLoadsAndNeverWipesConfig(t *testing.T) {
	root, _ := filepath.EvalSymlinks(t.TempDir())
	kept, gone, added := filepath.Join(root, "kept"), filepath.Join(root, "gone"), filepath.Join(root, "added")
	for _, dir := range []string{kept, added} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	configPath := writeProjectsConfig(t, kept, gone)
	cfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("a missing project directory must not fail loading: %v", err)
	}
	if len(cfg.Projects) != 1 || len(cfg.MissingProjects) != 1 || cfg.MissingProjects[0].Path != gone {
		t.Fatalf("projects=%#v missing=%#v", cfg.Projects, cfg.MissingProjects)
	}
	// Regression: Mutate once treated the wrapped ErrNotExist as a missing
	// config file and rewrote an empty configuration.
	if err := Mutate(configPath, func(current *Config) (bool, error) {
		updated, err := ReplaceProjectPaths(*current, []string{kept, added})
		*current = updated
		return true, err
	}); err != nil {
		t.Fatal(err)
	}
	contents, _ := os.ReadFile(configPath)
	for _, path := range []string{kept, gone, added} {
		if !strings.Contains(string(contents), path) {
			t.Fatalf("config lost %s:\n%s", path, contents)
		}
	}
}

func TestRetireAndRestoreMissingProject(t *testing.T) {
	root, _ := filepath.EvalSymlinks(t.TempDir())
	gone := filepath.Join(root, "gone")
	configPath := writeProjectsConfig(t, gone)
	now := time.Date(2026, 10, 4, 12, 0, 0, 0, time.UTC)
	var retired []RetiredProject
	if err := Mutate(configPath, func(cfg *Config) (bool, error) {
		retired = RetireMissingProjects(cfg, now)
		return true, nil
	}); err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(configPath)
	if err != nil {
		t.Fatal(err)
	}
	if len(retired) != 1 || len(cfg.MissingProjects) != 0 || len(cfg.RetiredProjects) != 1 ||
		cfg.RetiredProjects[0].Reason != RetiredMissingDirectory || !cfg.RetiredProjects[0].RetiredAt.Equal(now) {
		t.Fatalf("retired=%#v cfg=%#v", retired, cfg)
	}
	if err := RestoreRetiredProject(&cfg, gone); err == nil {
		t.Fatal("restoring before the directory exists must fail")
	}
	if err := os.MkdirAll(gone, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := RestoreRetiredProject(&cfg, gone); err != nil {
		t.Fatal(err)
	}
	if len(cfg.RetiredProjects) != 0 || len(cfg.Projects) != 1 || cfg.Projects[0].Path != gone {
		t.Fatalf("restored cfg = %#v", cfg)
	}
}
