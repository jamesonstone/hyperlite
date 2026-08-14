package pinboard

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const (
	sectionOneID = "11111111111111111111111111111111"
	sectionTwoID = "22222222222222222222222222222222"
	noteOneID    = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	noteTwoID    = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

func TestResolveRootUsesPrivateHyperliteDataDirectory(t *testing.T) {
	dataRoot := t.TempDir()
	t.Setenv(rootOverrideEnv, "")
	t.Setenv("XDG_DATA_HOME", dataRoot)
	root, err := ResolveRoot()
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(dataRoot, "hyperlite", "board")
	if root != want {
		t.Fatalf("root = %q, want %q", root, want)
	}
}

func TestStoreSeparatesContentFromLayoutAndPreservesRecency(t *testing.T) {
	root := filepath.Join(t.TempDir(), "board")
	now := time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC)
	store := deterministicStore(root, &now, sectionOneID, noteOneID, noteTwoID)

	snapshot := mustMutate(t, store, Mutation{Kind: MutationAddSection, Title: "Ideas"})
	section := snapshot.Board.Sections[0]
	if section.ID != sectionOneID || section.Title != "Ideas" {
		t.Fatalf("section = %#v", section)
	}

	snapshot = mustMutate(t, store, Mutation{
		Kind: MutationAddNote, SectionID: section.ID,
		Title: "First note", Description: "# Plain Markdown-compatible text\n",
	})
	note := snapshot.Notes[0]
	if note.ID != noteOneID || !note.CreatedAt.Equal(now) || !note.UpdatedAt.Equal(now) {
		t.Fatalf("note = %#v", note)
	}
	notePath := filepath.Join(root, notesDirectory, note.ID+".md")
	before, err := os.ReadFile(notePath)
	if err != nil {
		t.Fatal(err)
	}

	moved := Frame{X: 72, Y: 91, Width: NoteWidth, Height: NoteHeight}
	snapshot = mustMutate(t, store, Mutation{
		Kind: MutationMoveNote, NoteID: note.ID, SectionID: section.ID, Frame: &moved,
	})
	after, err := os.ReadFile(notePath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("moving a note rewrote its canonical Markdown")
	}
	if !snapshot.Notes[0].UpdatedAt.Equal(now) {
		t.Fatal("moving a note changed Updated")
	}
	if snapshot.Board.Notes[0].Frame != moved {
		t.Fatalf("moved frame = %#v", snapshot.Board.Notes[0].Frame)
	}

	now = now.Add(time.Hour)
	snapshot = mustMutate(t, store, Mutation{
		Kind: MutationUpdateNote, NoteID: note.ID,
		Title: "First note", Description: "Changed content",
	})
	if !snapshot.Notes[0].CreatedAt.Equal(note.CreatedAt) || !snapshot.Notes[0].UpdatedAt.Equal(now) {
		t.Fatalf("updated note = %#v", snapshot.Notes[0])
	}
}

func TestForkArchiveRestoreAndSectionDeletionAreRecoverable(t *testing.T) {
	root := filepath.Join(t.TempDir(), "board")
	now := time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC)
	store := deterministicStore(root, &now, sectionOneID, noteOneID, noteTwoID)
	snapshot := mustMutate(t, store, Mutation{Kind: MutationAddSection, Title: "Work"})
	section := snapshot.Board.Sections[0]
	snapshot = mustMutate(t, store, Mutation{
		Kind: MutationAddNote, SectionID: section.ID,
		Title: "Source", Description: "Copied exactly",
	})
	sourceLayout := snapshot.Board.Notes[0]

	now = now.Add(time.Minute)
	snapshot = mustMutate(t, store, Mutation{Kind: MutationForkNote, NoteID: noteOneID})
	if len(snapshot.Notes) != 2 || snapshot.Notes[1].ID != noteTwoID ||
		snapshot.Notes[1].ForkedFrom != noteOneID || snapshot.Notes[1].Title != "Source" ||
		snapshot.Notes[1].Description != "Copied exactly" ||
		!snapshot.Notes[1].CreatedAt.Equal(now) || !snapshot.Notes[1].UpdatedAt.Equal(now) {
		t.Fatalf("fork = %#v", snapshot.Notes)
	}
	forkLayout := snapshot.Board.Notes[1]
	if forkLayout.Frame.X <= sourceLayout.Frame.X || forkLayout.Frame.Y <= sourceLayout.Frame.Y {
		t.Fatalf("fork should have a visible cascade offset: %#v", forkLayout.Frame)
	}

	snapshot = mustMutate(t, store, Mutation{Kind: MutationArchiveNote, NoteID: noteTwoID})
	if len(snapshot.Notes) != 1 || len(snapshot.Archive) != 1 {
		t.Fatalf("archived snapshot = %#v", snapshot)
	}
	archived := snapshot.Archive[0]
	if archived.ArchivedFromSectionID != section.ID || archived.ArchivedFromSectionTitle != section.Title || archived.ArchivedAt == nil {
		t.Fatalf("archive metadata = %#v", archived)
	}

	snapshot = mustMutate(t, store, Mutation{Kind: MutationRestoreNote, NoteID: noteTwoID})
	if len(snapshot.Notes) != 2 || len(snapshot.Archive) != 0 {
		t.Fatalf("restored snapshot = %#v", snapshot)
	}
	restored := snapshot.Notes[1]
	if restored.ArchivedAt != nil || !restored.CreatedAt.Equal(now) || !restored.UpdatedAt.Equal(now) {
		t.Fatalf("restore changed content metadata: %#v", restored)
	}

	if _, err := store.Mutate(Mutation{Kind: MutationDeleteSection, SectionID: section.ID}); err == nil || !strings.Contains(err.Error(), "contains notes") {
		t.Fatalf("nonempty delete error = %v", err)
	}
	snapshot = mustMutate(t, store, Mutation{
		Kind: MutationDeleteSection, SectionID: section.ID, ArchiveNotes: true,
	})
	if len(snapshot.Board.Sections) != 0 || len(snapshot.Notes) != 0 || len(snapshot.Archive) != 2 {
		t.Fatalf("archive-and-delete snapshot = %#v", snapshot)
	}
}

func TestMalformedLayoutFailsClosedWithoutOverwrite(t *testing.T) {
	root := filepath.Join(t.TempDir(), "board")
	now := time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC)
	store := deterministicStore(root, &now, sectionOneID)
	mustMutate(t, store, Mutation{Kind: MutationAddSection, Title: "Safe"})
	path := filepath.Join(root, boardFileName)
	malformed := []byte(`{"schema_version":1,"sections":[`)
	if err := os.WriteFile(path, malformed, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Mutate(Mutation{Kind: MutationAddSection, Title: "Must not write"}); err == nil {
		t.Fatal("malformed layout should block mutation")
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(contents, malformed) {
		t.Fatalf("malformed source was overwritten: %q", contents)
	}
}

func TestStoreUsesPrivateRegularFilesAndRejectsUnsafeSources(t *testing.T) {
	root := filepath.Join(t.TempDir(), "board")
	now := time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC)
	store := deterministicStore(root, &now, sectionOneID, noteOneID)
	snapshot := mustMutate(t, store, Mutation{Kind: MutationAddSection, Title: "Private"})
	mustMutate(t, store, Mutation{Kind: MutationAddNote, SectionID: snapshot.Board.Sections[0].ID, Title: "Note"})
	for _, path := range []string{
		filepath.Join(root, boardFileName),
		filepath.Join(root, notesDirectory, noteOneID+".md"),
	} {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o600 {
			t.Fatalf("mode for %s = %o", path, info.Mode().Perm())
		}
	}
	target := filepath.Join(t.TempDir(), "target.json")
	if err := os.WriteFile(target, []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(root, boardFileName)); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(root, boardFileName)); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Load(); err == nil || !strings.Contains(err.Error(), "regular file") {
		t.Fatalf("symlink load error = %v", err)
	}
}

func TestStoreRejectsOrphanActiveNotesAndArchivedIDReuse(t *testing.T) {
	t.Run("orphan active note", func(t *testing.T) {
		root := filepath.Join(t.TempDir(), "board")
		store := Store{Root: root}
		if _, err := store.Load(); err != nil {
			t.Fatal(err)
		}
		now := time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC)
		orphan := Note{
			ID: noteOneID, Title: "Recoverable orphan", CreatedAt: now, UpdatedAt: now,
		}
		if err := writeNoteFile(root, orphan, false, true); err != nil {
			t.Fatal(err)
		}
		if _, err := store.Load(); err == nil || !strings.Contains(err.Error(), "do not match layout membership") {
			t.Fatalf("orphan load error = %v", err)
		}
		if _, err := os.Stat(filepath.Join(root, notesDirectory, noteOneID+".md")); err != nil {
			t.Fatalf("recoverable orphan was not preserved: %v", err)
		}
	})

	t.Run("archived id reuse", func(t *testing.T) {
		root := filepath.Join(t.TempDir(), "board")
		now := time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC)
		store := deterministicStore(root, &now, sectionOneID, noteOneID, noteOneID)
		snapshot := mustMutate(t, store, Mutation{Kind: MutationAddSection, Title: "Ideas"})
		sectionID := snapshot.Board.Sections[0].ID
		mustMutate(t, store, Mutation{Kind: MutationAddNote, SectionID: sectionID, Title: "Original"})
		mustMutate(t, store, Mutation{Kind: MutationArchiveNote, NoteID: noteOneID})

		if _, err := store.Mutate(Mutation{
			Kind: MutationAddNote, SectionID: sectionID, Title: "Collision",
		}); err == nil || !strings.Contains(err.Error(), "already exists") {
			t.Fatalf("archived id collision error = %v", err)
		}
		snapshot, err := store.Load()
		if err != nil {
			t.Fatal(err)
		}
		if len(snapshot.Notes) != 0 || len(snapshot.Archive) != 1 || snapshot.Archive[0].Title != "Original" {
			t.Fatalf("collision changed state: %#v", snapshot)
		}
	})
}

func deterministicStore(root string, now *time.Time, ids ...string) Store {
	index := 0
	return Store{
		Root: root,
		Now:  func() time.Time { return *now },
		NewID: func() (string, error) {
			if index >= len(ids) {
				return "", os.ErrNotExist
			}
			id := ids[index]
			index++
			return id, nil
		},
	}
}

func mustMutate(t *testing.T, store Store, mutation Mutation) Snapshot {
	t.Helper()
	snapshot, err := store.Mutate(mutation)
	if err != nil {
		t.Fatal(err)
	}
	return snapshot
}
