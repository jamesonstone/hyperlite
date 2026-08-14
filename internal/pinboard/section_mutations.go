package pinboard

import (
	"errors"
	"strings"
)

func (s Store) addSection(root string, snapshot *Snapshot, mutation Mutation) error {
	if len(snapshot.Board.Sections) >= MaxSections {
		return errors.New("pinboard section limit reached")
	}
	title := strings.TrimSpace(mutation.Title)
	if err := validateTitle(title, "section"); err != nil {
		return err
	}
	id, err := s.newID()
	if err != nil {
		return err
	}
	frame := defaultSectionFrame(len(snapshot.Board.Sections), snapshot.Board.Size)
	if mutation.Frame != nil {
		frame = *mutation.Frame
	}
	snapshot.Board.Sections = append(snapshot.Board.Sections, Section{ID: id, Title: title, Frame: frame})
	return writeBoard(root, snapshot.Board)
}

func renameSection(root string, snapshot *Snapshot, mutation Mutation) error {
	index, _, err := findSection(snapshot.Board, mutation.SectionID)
	if err != nil {
		return err
	}
	title := strings.TrimSpace(mutation.Title)
	if err := validateTitle(title, "section"); err != nil {
		return err
	}
	snapshot.Board.Sections[index].Title = title
	return writeBoard(root, snapshot.Board)
}

func updateSectionFrame(root string, snapshot *Snapshot, mutation Mutation) error {
	index, section, err := findSection(snapshot.Board, mutation.SectionID)
	if err != nil {
		return err
	}
	if mutation.Frame == nil {
		return errors.New("section frame is required")
	}
	if err := validateSectionFrame(*mutation.Frame, snapshot.Board.Size); err != nil {
		return err
	}
	snapshot.Board.Sections[index].Frame = *mutation.Frame
	for noteIndex := range snapshot.Board.Notes {
		if snapshot.Board.Notes[noteIndex].SectionID == section.ID {
			snapshot.Board.Notes[noteIndex].Frame = clampNoteFrame(
				snapshot.Board.Notes[noteIndex].Frame, *mutation.Frame,
			)
		}
	}
	return writeBoard(root, snapshot.Board)
}

func (s Store) deleteSection(root string, snapshot *Snapshot, mutation Mutation) error {
	index, section, err := findSection(snapshot.Board, mutation.SectionID)
	if err != nil {
		return err
	}
	noteIDs := noteIDsInSection(snapshot.Board, section.ID)
	if len(noteIDs) > 0 && !mutation.ArchiveNotes {
		return errors.New("section contains notes; archive them explicitly before deletion")
	}
	if len(snapshot.Archive)+len(noteIDs) > MaxArchivedNotes {
		return errors.New("pinboard archive limit reached")
	}
	createdArchives := []string{}
	if len(noteIDs) > 0 {
		archivedAt := s.now()
		for _, id := range noteIDs {
			note, loadErr := loadNoteFile(root, id, false)
			if loadErr != nil {
				rollbackArchives(root, createdArchives)
				return loadErr
			}
			note.ArchivedAt = &archivedAt
			note.ArchivedFromSectionID, note.ArchivedFromSectionTitle = section.ID, section.Title
			if writeErr := writeNoteFile(root, note, true, true); writeErr != nil {
				rollbackArchives(root, createdArchives)
				return writeErr
			}
			createdArchives = append(createdArchives, id)
		}
	}
	snapshot.Board.Sections = append(snapshot.Board.Sections[:index], snapshot.Board.Sections[index+1:]...)
	snapshot.Board.Notes = removeLayouts(snapshot.Board.Notes, noteIDs)
	if err := writeBoard(root, snapshot.Board); err != nil {
		rollbackArchives(root, createdArchives)
		return err
	}
	for _, id := range noteIDs {
		if err := removeNoteFile(root, id, false); err != nil {
			return err
		}
	}
	return nil
}

func defaultSectionFrame(index int, board Size) Frame {
	x := 24.0 + float64(index%4)*344
	y := 24.0 + float64(index/4)*584
	frame := Frame{X: x, Y: y, Width: DefaultSectionWidth, Height: DefaultSectionHeight}
	if frame.X+frame.Width > board.Width {
		frame.X = max(board.Width-frame.Width, 0)
	}
	if frame.Y+frame.Height > board.Height {
		frame.Y = max(board.Height-frame.Height, 0)
	}
	return frame
}
