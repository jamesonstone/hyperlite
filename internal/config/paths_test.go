package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCanonicalizeSourcePathResolvesAncestorsButRejectsFinalSymlink(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HOME", root)
	realParent := filepath.Join(root, "real")
	realSource := filepath.Join(realParent, "source")
	if err := os.MkdirAll(realSource, 0o755); err != nil {
		t.Fatal(err)
	}
	linkedParent := filepath.Join(root, "linked-parent")
	if err := os.Symlink(realParent, linkedParent); err != nil {
		t.Fatal(err)
	}
	resolved, err := CanonicalizeSourcePath(filepath.Join(linkedParent, "source"))
	canonicalRealSource, evalErr := filepath.EvalSymlinks(realSource)
	if evalErr != nil {
		t.Fatal(evalErr)
	}
	if err != nil || resolved != canonicalRealSource {
		t.Fatalf("resolved = %q, %v", resolved, err)
	}
	canonicalHome, err := filepath.EvalSymlinks(root)
	if err != nil {
		t.Fatal(err)
	}
	resolved, err = CanonicalizeSourcePath("~")
	if err != nil || resolved != canonicalHome {
		t.Fatalf("bare home = %q, %v; want %q", resolved, err, canonicalHome)
	}
	resolved, err = CanonicalizeSourcePath("~/real/source")
	if err != nil || resolved != canonicalRealSource {
		t.Fatalf("home source = %q, %v; want %q", resolved, err, canonicalRealSource)
	}
	finalLink := filepath.Join(root, "source-link")
	if err := os.Symlink(realSource, finalLink); err != nil {
		t.Fatal(err)
	}
	if _, err := CanonicalizeSourcePath(finalLink); err == nil || !strings.Contains(err.Error(), "symbolic link") {
		t.Fatalf("final symlink error = %v", err)
	}
}
