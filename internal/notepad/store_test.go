package notepad

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestResolveRootUsesNotesDirectoryUnderXDGDataHome(t *testing.T) {
	root := t.TempDir()
	t.Setenv(notesOverrideEnv, "")
	t.Setenv(legacyOverrideEnv, "")
	t.Setenv("XDG_DATA_HOME", root)
	resolved, err := ResolveRoot()
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(root, "hyperlite", "notes")
	if resolved != want {
		t.Fatalf("root = %q, want %q", resolved, want)
	}
	pinned, err := ResolvePinnedPath()
	if err != nil {
		t.Fatal(err)
	}
	if pinned != filepath.Join(want, pinnedFileName) {
		t.Fatalf("pinned path = %q", pinned)
	}
}

func TestResolveRootHonorsNewOverrideAndDerivesFromLegacyOverride(t *testing.T) {
	root := filepath.Join(t.TempDir(), "custom-notes")
	t.Setenv(notesOverrideEnv, root)
	t.Setenv(legacyOverrideEnv, filepath.Join(t.TempDir(), legacyTextFileName))
	resolved, err := ResolveRoot()
	if err != nil {
		t.Fatal(err)
	}
	if resolved != root {
		t.Fatalf("new override root = %q, want %q", resolved, root)
	}

	t.Setenv(notesOverrideEnv, "")
	legacy := filepath.Join(t.TempDir(), "legacy", legacyTextFileName)
	t.Setenv(legacyOverrideEnv, legacy)
	resolved, err = ResolveRoot()
	if err != nil {
		t.Fatal(err)
	}
	if resolved != filepath.Join(filepath.Dir(legacy), "notes") {
		t.Fatalf("legacy-derived root = %q", resolved)
	}
}

func TestStoreWritesPrivateAtomicMarkdownDocuments(t *testing.T) {
	root := filepath.Join(t.TempDir(), "notes")
	store := Store{Root: root}
	pinned, err := store.WritePinned("# Durable context\n")
	if err != nil {
		t.Fatal(err)
	}
	daily, err := store.WriteDaily("2026-08-02", "# Today\n")
	if err != nil {
		t.Fatal(err)
	}
	for _, document := range []Document{pinned, daily} {
		if !document.Exists || filepath.Ext(document.Path) != ".md" {
			t.Fatalf("document = %#v", document)
		}
		info, statErr := os.Stat(document.Path)
		if statErr != nil {
			t.Fatal(statErr)
		}
		if info.Mode().Perm() != 0o600 {
			t.Fatalf("file mode = %o", info.Mode().Perm())
		}
		directoryInfo, statErr := os.Stat(filepath.Dir(document.Path))
		if statErr != nil {
			t.Fatal(statErr)
		}
		if directoryInfo.Mode().Perm() != 0o700 {
			t.Fatalf("directory mode = %o", directoryInfo.Mode().Perm())
		}
	}
	matches, err := filepath.Glob(filepath.Join(root, dailyDirectoryName, ".hyperlite-note-*.md"))
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 0 {
		t.Fatalf("temporary files remain: %v", matches)
	}
}

func TestLoadDailyIsLazyAndUsesDirectDatePath(t *testing.T) {
	root := filepath.Join(t.TempDir(), "notes")
	store := Store{Root: root}
	document, err := store.LoadDaily("2026-08-02")
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(root, dailyDirectoryName, "2026-08-02.md")
	if document.Exists || document.Path != want || document.Content != "" {
		t.Fatalf("missing daily document = %#v", document)
	}
	if _, err := os.Stat(want); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("load created daily file: %v", err)
	}
}

func TestStoreAdoptsLegacyDefaultTextAsPinnedMarkdown(t *testing.T) {
	dataRoot := t.TempDir()
	t.Setenv(notesOverrideEnv, "")
	t.Setenv(legacyOverrideEnv, "")
	t.Setenv("XDG_DATA_HOME", dataRoot)
	directory := filepath.Join(dataRoot, "hyperlite")
	if err := os.MkdirAll(directory, 0o700); err != nil {
		t.Fatal(err)
	}
	legacy := filepath.Join(directory, legacyTextFileName)
	content := "# Kept verbatim\n\nNo formatting is applied.\n"
	if err := os.WriteFile(legacy, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	document, err := (Store{}).LoadPinned()
	if err != nil {
		t.Fatal(err)
	}
	current := filepath.Join(directory, "notes", pinnedFileName)
	if document.Path != current || document.Content != content || !document.Exists {
		t.Fatalf("document = %#v", document)
	}
	if _, err := os.Stat(legacy); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("legacy file remains: %v", err)
	}
}

func TestStoreAdoptsExplicitLegacyPathOnlyWhenPinnedIsMissing(t *testing.T) {
	directory := t.TempDir()
	legacy := filepath.Join(directory, "old.md")
	root := filepath.Join(directory, "notes")
	if err := os.WriteFile(legacy, []byte("legacy"), 0o600); err != nil {
		t.Fatal(err)
	}
	store := Store{Root: root, LegacyPath: legacy}
	document, err := store.LoadPinned()
	if err != nil {
		t.Fatal(err)
	}
	if document.Content != "legacy" {
		t.Fatalf("migrated content = %q", document.Content)
	}
	if _, err := store.WritePinned("current"); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(legacy, []byte("stale"), 0o600); err != nil {
		t.Fatal(err)
	}
	document, err = store.LoadPinned()
	if err != nil {
		t.Fatal(err)
	}
	if document.Content != "current" {
		t.Fatalf("legacy replaced current pinned content: %q", document.Content)
	}
}

func TestDocumentsIncludesPinnedAndExistingDailyNotes(t *testing.T) {
	root := filepath.Join(t.TempDir(), "notes")
	store := Store{Root: root}
	if _, err := store.WriteDaily("2026-08-01", "older"); err != nil {
		t.Fatal(err)
	}
	if _, err := store.WriteDaily("2026-08-02", "newer"); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, dailyDirectoryName, "README.md"), []byte("ignored"), 0o600); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(t.TempDir(), "unusable.md")
	if err := os.WriteFile(target, []byte("not indexed"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(root, dailyDirectoryName, "2026-08-03.md")); err != nil {
		t.Fatal(err)
	}
	documents, err := store.Documents()
	if err != nil {
		t.Fatal(err)
	}
	if len(documents) != 3 {
		t.Fatalf("documents = %#v", documents)
	}
	if documents[0].Kind != KindPinned || documents[0].Exists {
		t.Fatalf("virtual pinned document = %#v", documents[0])
	}
	if documents[1].Date != "2026-08-02" || documents[1].Content != "newer" ||
		documents[2].Date != "2026-08-01" || documents[2].Content != "older" {
		t.Fatalf("daily documents = %#v", documents[1:])
	}
}

func TestStoreRejectsInvalidDatesContentAndSymlinks(t *testing.T) {
	root := filepath.Join(t.TempDir(), "notes")
	store := Store{Root: root}
	for _, date := range []string{"", "2026-8-2", "2026-02-30", "../2026-08-02"} {
		if _, err := store.LoadDaily(date); err == nil {
			t.Fatalf("expected invalid date error for %q", date)
		}
	}
	if _, err := store.WritePinned(strings.Repeat("x", MaxBytes+1)); err == nil {
		t.Fatal("expected oversized content error")
	}
	if _, err := store.WritePinned("bad\x00content"); err == nil {
		t.Fatal("expected NUL content error")
	}
	if _, err := store.WritePinned(string([]byte{0xff})); err == nil {
		t.Fatal("expected UTF-8 content error")
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(t.TempDir(), "target.md")
	if err := os.WriteFile(target, []byte("target"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(root, pinnedFileName)); err != nil {
		t.Fatal(err)
	}
	if _, err := store.LoadPinned(); err == nil || !strings.Contains(err.Error(), "regular file") {
		t.Fatalf("symlink error = %v", err)
	}
}

func TestStoreSerializesConcurrentWriters(t *testing.T) {
	root := filepath.Join(t.TempDir(), "notes")
	store := Store{Root: root}
	values := []string{
		strings.Repeat("a", 32*1024),
		strings.Repeat("b", 32*1024),
		strings.Repeat("c", 32*1024),
	}
	var wait sync.WaitGroup
	errors := make(chan error, len(values))
	for _, value := range values {
		value := value
		wait.Add(1)
		go func() {
			defer wait.Done()
			_, err := store.WriteDaily("2026-08-02", value)
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
	document, err := store.LoadDaily("2026-08-02")
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
	root := filepath.Join(t.TempDir(), "notes")
	if err := os.MkdirAll(root, 0o700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, pinnedFileName)
	if err := os.WriteFile(path, []byte(strings.Repeat("x", MaxBytes+1)), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := (Store{Root: root}).LoadPinned(); err == nil ||
		!strings.Contains(err.Error(), "exceeds") {
		t.Fatalf("oversized load error = %v", err)
	}
}
