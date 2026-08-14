package pinboard

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestStorePreservesAndReconcilesResidualNoteFiles(t *testing.T) {
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
		snapshot, err := store.Load()
		if err != nil {
			t.Fatal(err)
		}
		if len(snapshot.Notes) != 0 || len(snapshot.Archive) != 0 {
			t.Fatalf("orphan should not become board state: %#v", snapshot)
		}
		if _, err := os.Stat(filepath.Join(root, notesDirectory, noteOneID+".md")); err != nil {
			t.Fatalf("recoverable orphan was not preserved: %v", err)
		}
	})

	t.Run("interrupted archive and restore", func(t *testing.T) {
		root := filepath.Join(t.TempDir(), "board")
		now := time.Date(2026, 8, 14, 12, 0, 0, 0, time.UTC)
		store := deterministicStore(root, &now, sectionOneID, noteOneID)
		snapshot := mustMutate(t, store, Mutation{Kind: MutationAddSection, Title: "Ideas"})
		section := snapshot.Board.Sections[0]
		snapshot = mustMutate(t, store, Mutation{
			Kind: MutationAddNote, SectionID: section.ID, Title: "Recoverable",
		})

		residualArchive := snapshot.Notes[0]
		residualArchive.ArchivedAt = &now
		residualArchive.ArchivedFromSectionID = section.ID
		residualArchive.ArchivedFromSectionTitle = section.Title
		if err := writeNoteFile(root, residualArchive, true, true); err != nil {
			t.Fatal(err)
		}
		snapshot, err := store.Load()
		if err != nil {
			t.Fatal(err)
		}
		if len(snapshot.Notes) != 1 || len(snapshot.Archive) != 0 {
			t.Fatalf("active layout should win residual archive: %#v", snapshot)
		}

		snapshot = mustMutate(t, store, Mutation{Kind: MutationArchiveNote, NoteID: noteOneID})
		residualActive := snapshot.Archive[0]
		residualActive.ArchivedAt = nil
		residualActive.ArchivedFromSectionID = ""
		residualActive.ArchivedFromSectionTitle = ""
		if err := writeNoteFile(root, residualActive, false, true); err != nil {
			t.Fatal(err)
		}
		snapshot, err = store.Load()
		if err != nil {
			t.Fatal(err)
		}
		if len(snapshot.Notes) != 0 || len(snapshot.Archive) != 1 {
			t.Fatalf("archived layout should win residual active file: %#v", snapshot)
		}
		snapshot = mustMutate(t, store, Mutation{Kind: MutationRestoreNote, NoteID: noteOneID})
		if len(snapshot.Notes) != 1 || len(snapshot.Archive) != 0 {
			t.Fatalf("restore retry should reconcile residual active file: %#v", snapshot)
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
