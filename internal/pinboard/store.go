package pinboard

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"path/filepath"
	"time"
)

type Store struct {
	Root  string
	Now   func() time.Time
	NewID func() (string, error)
}

func (s Store) Load() (Snapshot, error) {
	root, err := s.root()
	if err != nil {
		return Snapshot{}, err
	}
	var snapshot Snapshot
	err = withLock(root, func() error {
		var loadErr error
		snapshot, loadErr = loadSnapshot(root)
		return loadErr
	})
	return snapshot, err
}

func (s Store) Mutate(mutation Mutation) (Snapshot, error) {
	root, err := s.root()
	if err != nil {
		return Snapshot{}, err
	}
	var snapshot Snapshot
	err = withLock(root, func() error {
		current, loadErr := loadSnapshot(root)
		if loadErr != nil {
			return loadErr
		}
		if mutationErr := s.apply(root, &current, mutation); mutationErr != nil {
			return mutationErr
		}
		var reloadErr error
		snapshot, reloadErr = loadSnapshot(root)
		return reloadErr
	})
	return snapshot, err
}

func loadSnapshot(root string) (Snapshot, error) {
	board, err := loadBoard(root)
	if err != nil {
		return Snapshot{}, err
	}
	activeIDs, err := listNoteIDs(root, notesDirectory, MaxActiveNotes)
	if err != nil {
		return Snapshot{}, err
	}
	placements := make(map[string]struct{}, len(board.Notes))
	for _, placement := range board.Notes {
		placements[placement.NoteID] = struct{}{}
	}
	if len(activeIDs) != len(placements) {
		return Snapshot{}, fmt.Errorf("pinboard active note files do not match layout membership")
	}
	for _, id := range activeIDs {
		if _, exists := placements[id]; !exists {
			return Snapshot{}, fmt.Errorf("pinboard active note %s has no layout membership", id)
		}
	}
	notes := make([]Note, 0, len(board.Notes))
	for _, placement := range board.Notes {
		note, loadErr := loadNoteFile(root, placement.NoteID, false)
		if loadErr != nil {
			return Snapshot{}, loadErr
		}
		notes = append(notes, note)
	}
	archive, err := loadArchive(root)
	if err != nil {
		return Snapshot{}, err
	}
	for _, note := range archive {
		if _, active := placements[note.ID]; active {
			return Snapshot{}, fmt.Errorf("pinboard note %s exists in both active storage and archive", note.ID)
		}
	}
	return Snapshot{Board: board, Notes: notes, Archive: archive}, nil
}

func (s Store) apply(root string, snapshot *Snapshot, mutation Mutation) error {
	switch mutation.Kind {
	case MutationAddSection:
		return s.addSection(root, snapshot, mutation)
	case MutationRenameSection:
		return renameSection(root, snapshot, mutation)
	case MutationUpdateSectionFrame:
		return updateSectionFrame(root, snapshot, mutation)
	case MutationDeleteSection:
		return s.deleteSection(root, snapshot, mutation)
	case MutationAddNote:
		return s.addNote(root, snapshot, mutation)
	case MutationUpdateNote:
		return s.updateNote(root, snapshot, mutation)
	case MutationMoveNote:
		return moveNote(root, snapshot, mutation)
	case MutationForkNote:
		return s.forkNote(root, snapshot, mutation)
	case MutationArchiveNote:
		return s.archiveNote(root, snapshot, mutation.NoteID)
	case MutationRestoreNote:
		return s.restoreNote(root, snapshot, mutation)
	default:
		return fmt.Errorf("unsupported pinboard mutation %q", mutation.Kind)
	}
}

func (s Store) root() (string, error) {
	if s.Root != "" {
		return filepath.Abs(s.Root)
	}
	return ResolveRoot()
}
func (s Store) now() time.Time {
	if s.Now != nil {
		return s.Now().UTC()
	}
	return time.Now().UTC()
}
func (s Store) newID() (string, error) {
	if s.NewID != nil {
		return s.NewID()
	}
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

func findSection(board Board, id string) (int, Section, error) {
	for index, section := range board.Sections {
		if section.ID == id {
			return index, section, nil
		}
	}
	return -1, Section{}, fmt.Errorf("unknown section %s", id)
}
func findLayout(board Board, id string) (int, NoteLayout, error) {
	for index, layout := range board.Notes {
		if layout.NoteID == id {
			return index, layout, nil
		}
	}
	return -1, NoteLayout{}, fmt.Errorf("unknown note %s", id)
}
func noteCountInSection(board Board, id string) int {
	count := 0
	for _, note := range board.Notes {
		if note.SectionID == id {
			count++
		}
	}
	return count
}
func noteIDsInSection(board Board, id string) []string {
	ids := []string{}
	for _, note := range board.Notes {
		if note.SectionID == id {
			ids = append(ids, note.NoteID)
		}
	}
	return ids
}
func removeLayouts(layouts []NoteLayout, ids []string) []NoteLayout {
	removed := map[string]struct{}{}
	for _, id := range ids {
		removed[id] = struct{}{}
	}
	kept := layouts[:0]
	for _, layout := range layouts {
		if _, ok := removed[layout.NoteID]; !ok {
			kept = append(kept, layout)
		}
	}
	return kept
}
func rollbackArchives(root string, ids []string) {
	for _, id := range ids {
		_ = removeNoteFile(root, id, true)
	}
}

func noteIDExists(snapshot Snapshot, id string) bool {
	for _, note := range snapshot.Notes {
		if note.ID == id {
			return true
		}
	}
	for _, note := range snapshot.Archive {
		if note.ID == id {
			return true
		}
	}
	return false
}
