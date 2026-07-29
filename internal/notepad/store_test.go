package notepad

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestResolvePathUsesXDGDataHome(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HYPERLITE_NOTEPAD_PATH", "")
	t.Setenv("XDG_DATA_HOME", root)
	path, err := ResolvePath()
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(root, "hyperlite", "notepad.md")
	if path != want {
		t.Fatalf("path = %q, want %q", path, want)
	}
}

func TestStoreWritesPrivateAtomicDocument(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", "notepad.md")
	store := Store{Path: path}
	document, err := store.Write("# Working context\n\nDeploy after migration.\n")
	if err != nil {
		t.Fatal(err)
	}
	if document.Content != "# Working context\n\nDeploy after migration.\n" {
		t.Fatalf("content = %q", document.Content)
	}
	fileInfo, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if fileInfo.Mode().Perm() != 0o600 {
		t.Fatalf("file mode = %o", fileInfo.Mode().Perm())
	}
	directoryInfo, err := os.Stat(filepath.Dir(path))
	if err != nil {
		t.Fatal(err)
	}
	if directoryInfo.Mode().Perm() != 0o700 {
		t.Fatalf("directory mode = %o", directoryInfo.Mode().Perm())
	}
	matches, err := filepath.Glob(filepath.Join(filepath.Dir(path), ".hyperlite-notepad-*.md"))
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 0 {
		t.Fatalf("temporary files remain: %v", matches)
	}
}

func TestStoreRejectsOversizedNULAndSymlinkContent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notepad.md")
	store := Store{Path: path}
	if _, err := store.Write(strings.Repeat("x", MaxBytes+1)); err == nil {
		t.Fatal("expected oversized content error")
	}
	if _, err := store.Write("bad\x00content"); err == nil {
		t.Fatal("expected NUL content error")
	}
	target := filepath.Join(t.TempDir(), "target.md")
	if err := os.WriteFile(target, []byte("target"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, path); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Load(); err == nil || !strings.Contains(err.Error(), "regular file") {
		t.Fatalf("symlink error = %v", err)
	}
}

func TestStoreSerializesConcurrentWriters(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notepad.md")
	store := Store{Path: path}
	values := []string{
		strings.Repeat("a", 32*1024),
		strings.Repeat("b", 32*1024),
		strings.Repeat("c", 32*1024),
	}
	var wait sync.WaitGroup
	errors := make(chan error, len(values))
	for _, value := range values {
		wait.Add(1)
		go func() {
			defer wait.Done()
			_, err := store.Write(value)
			errors <- err
		}()
	}
	wait.Wait()
	close(errors)
	for err := range errors {
		if err != nil {
			t.Fatal(err)
		}
	}
	document, err := store.Load()
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range values {
		if document.Content == value {
			return
		}
	}
	t.Fatalf("document was torn: %d bytes", len(document.Content))
}

func TestLoadRejectsOversizedExistingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notepad.md")
	if err := os.WriteFile(path, []byte(strings.Repeat("x", MaxBytes+1)), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := (Store{Path: path}).Load(); err == nil ||
		!strings.Contains(err.Error(), "exceeds") {
		t.Fatalf("oversized load error = %v", err)
	}
}
