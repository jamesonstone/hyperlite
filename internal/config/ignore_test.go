package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestIgnoredProjectsPersistAndSurviveSelectionChanges(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	first, second := filepath.Join(root, "first"), filepath.Join(root, "second")
	for _, dir := range []string{first, second} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	cfg := Config{Version: Version, Projects: []Source{{Path: first}, {Path: second}}}
	if changed, err := SetProjectIgnored(&cfg, first, true); err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	if changed, _ := SetProjectIgnored(&cfg, first, true); changed {
		t.Fatal("repeating ignore must not report a change")
	}
	if _, err := SetProjectIgnored(&cfg, filepath.Join(root, "missing"), true); err == nil {
		t.Fatal("ignoring an unconfigured project must fail")
	}
	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := (AtomicWriter{}).Write(path, cfg); err != nil {
		t.Fatal(err)
	}
	contents, _ := os.ReadFile(path)
	if strings.Count(string(contents), "ignored: true") != 1 {
		t.Fatalf("config = %s", contents)
	}
	loaded, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	replaced, err := ReplaceProjectPaths(loaded, []string{second, first})
	if err != nil {
		t.Fatal(err)
	}
	if !replaced.Projects[0].Ignored || replaced.Projects[1].Ignored {
		t.Fatalf("projects = %#v", replaced.Projects)
	}
}
