package pinboard

import (
	"errors"
	"fmt"
	"strings"
)

func (s Store) addNote(root string, snapshot *Snapshot, mutation Mutation) error {
	if len(snapshot.Board.Notes) >= MaxActiveNotes {
		return errors.New("active pinboard note limit reached")
	}
	_, section, err := findSection(snapshot.Board, mutation.SectionID)
	if err != nil {
		return err
	}
	title := strings.TrimSpace(mutation.Title)
	now := s.now()
	id, err := s.newID()
	if err != nil {
		return err
	}
	if noteIDExists(*snapshot, id) {
		return fmt.Errorf("note id %s already exists", id)
	}
	note := Note{ID: id, Title: title, Description: mutation.Description, CreatedAt: now, UpdatedAt: now}
	if err := validateNote(note, false); err != nil {
		return err
	}
	frame := defaultNoteFrame(noteCountInSection(snapshot.Board, section.ID), section.Frame)
	if mutation.Frame != nil {
		frame = clampNoteFrame(*mutation.Frame, section.Frame)
	}
	if err := writeNoteFile(root, note, false, true); err != nil {
		return err
	}
	snapshot.Board.Notes = append(snapshot.Board.Notes, NoteLayout{NoteID: id, SectionID: section.ID, Frame: frame})
	if err := writeBoard(root, snapshot.Board); err != nil {
		_ = removeNoteFile(root, id, false)
		return err
	}
	return nil
}

func (s Store) updateNote(root string, snapshot *Snapshot, mutation Mutation) error {
	if _, _, err := findLayout(snapshot.Board, mutation.NoteID); err != nil {
		return err
	}
	note, err := loadNoteFile(root, mutation.NoteID, false)
	if err != nil {
		return err
	}
	title := strings.TrimSpace(mutation.Title)
	if title == note.Title && mutation.Description == note.Description {
		return nil
	}
	note.Title, note.Description, note.UpdatedAt = title, mutation.Description, s.now()
	return writeNoteFile(root, note, false, false)
}

func moveNote(root string, snapshot *Snapshot, mutation Mutation) error {
	index, _, err := findLayout(snapshot.Board, mutation.NoteID)
	if err != nil {
		return err
	}
	_, section, err := findSection(snapshot.Board, mutation.SectionID)
	if err != nil {
		return err
	}
	if mutation.Frame == nil {
		return errors.New("note frame is required")
	}
	snapshot.Board.Notes[index].SectionID = section.ID
	snapshot.Board.Notes[index].Frame = clampNoteFrame(*mutation.Frame, section.Frame)
	return writeBoard(root, snapshot.Board)
}

func (s Store) forkNote(root string, snapshot *Snapshot, mutation Mutation) error {
	if len(snapshot.Board.Notes) >= MaxActiveNotes {
		return errors.New("active pinboard note limit reached")
	}
	_, placement, err := findLayout(snapshot.Board, mutation.NoteID)
	if err != nil {
		return err
	}
	_, section, err := findSection(snapshot.Board, placement.SectionID)
	if err != nil {
		return err
	}
	source, err := loadNoteFile(root, mutation.NoteID, false)
	if err != nil {
		return err
	}
	id, err := s.newID()
	if err != nil {
		return err
	}
	if noteIDExists(*snapshot, id) {
		return fmt.Errorf("note id %s already exists", id)
	}
	now := s.now()
	fork := Note{ID: id, Title: source.Title, Description: source.Description, CreatedAt: now, UpdatedAt: now, ForkedFrom: source.ID}
	if err := writeNoteFile(root, fork, false, true); err != nil {
		return err
	}
	frame := placement.Frame
	frame.X, frame.Y = frame.X+CascadeOffset, frame.Y+CascadeOffset
	frame = clampNoteFrame(frame, section.Frame)
	snapshot.Board.Notes = append(snapshot.Board.Notes, NoteLayout{NoteID: id, SectionID: section.ID, Frame: frame})
	if err := writeBoard(root, snapshot.Board); err != nil {
		_ = removeNoteFile(root, id, false)
		return err
	}
	return nil
}

func (s Store) archiveNote(root string, snapshot *Snapshot, noteID string) error {
	if len(snapshot.Archive) >= MaxArchivedNotes {
		return errors.New("pinboard archive limit reached")
	}
	index, placement, err := findLayout(snapshot.Board, noteID)
	if err != nil {
		return err
	}
	_, section, err := findSection(snapshot.Board, placement.SectionID)
	if err != nil {
		return err
	}
	note, err := loadNoteFile(root, noteID, false)
	if err != nil {
		return err
	}
	archivedAt := s.now()
	note.ArchivedAt = &archivedAt
	note.ArchivedFromSectionID, note.ArchivedFromSectionTitle = section.ID, section.Title
	if err := writeNoteFile(root, note, true, true); err != nil {
		return err
	}
	snapshot.Board.Notes = append(snapshot.Board.Notes[:index], snapshot.Board.Notes[index+1:]...)
	if err := writeBoard(root, snapshot.Board); err != nil {
		_ = removeNoteFile(root, noteID, true)
		return err
	}
	return removeNoteFile(root, noteID, false)
}

func (s Store) restoreNote(root string, snapshot *Snapshot, mutation Mutation) error {
	if len(snapshot.Board.Notes) >= MaxActiveNotes {
		return errors.New("active pinboard note limit reached")
	}
	note, err := loadNoteFile(root, mutation.NoteID, true)
	if err != nil {
		return err
	}
	sectionID := note.ArchivedFromSectionID
	if mutation.SectionID != "" {
		sectionID = mutation.SectionID
	}
	_, section, err := findSection(snapshot.Board, sectionID)
	if err != nil {
		return errors.New("restore destination section is required")
	}
	note.ArchivedAt = nil
	note.ArchivedFromSectionID, note.ArchivedFromSectionTitle = "", ""
	if err := writeNoteFile(root, note, false, true); err != nil {
		return err
	}
	frame := defaultNoteFrame(noteCountInSection(snapshot.Board, section.ID), section.Frame)
	snapshot.Board.Notes = append(snapshot.Board.Notes, NoteLayout{NoteID: note.ID, SectionID: section.ID, Frame: frame})
	if err := writeBoard(root, snapshot.Board); err != nil {
		_ = removeNoteFile(root, note.ID, false)
		return err
	}
	return removeNoteFile(root, note.ID, true)
}

func defaultNoteFrame(index int, section Frame) Frame {
	x := 18.0 + float64(index%2)*CascadeOffset
	y := 18.0 + float64(index/2)*CascadeOffset
	return clampNoteFrame(Frame{X: x, Y: y, Width: NoteWidth, Height: NoteHeight}, section)
}
