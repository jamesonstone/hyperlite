package pinboard

import (
	"errors"
	"fmt"
	"math"
	"regexp"
	"strings"
	"unicode/utf8"
)

var opaqueIDPattern = regexp.MustCompile(`^[a-f0-9]{32}$`)

func validateBoard(board Board) error {
	if board.SchemaVersion != SchemaVersion {
		return fmt.Errorf("unsupported pinboard schema version %d", board.SchemaVersion)
	}
	if !validDimension(board.Size.Width, 800, 4000) || !validDimension(board.Size.Height, 600, 3000) {
		return errors.New("pinboard size is outside supported bounds")
	}
	if len(board.Sections) > MaxSections || len(board.Notes) > MaxActiveNotes {
		return errors.New("pinboard item count exceeds supported bounds")
	}
	sections := make(map[string]Section, len(board.Sections))
	for _, section := range board.Sections {
		if !validID(section.ID) {
			return fmt.Errorf("invalid section id %q", section.ID)
		}
		if _, exists := sections[section.ID]; exists {
			return fmt.Errorf("duplicate section id %q", section.ID)
		}
		if err := validateTitle(section.Title, "section"); err != nil {
			return err
		}
		if err := validateSectionFrame(section.Frame, board.Size); err != nil {
			return fmt.Errorf("section %s: %w", section.ID, err)
		}
		sections[section.ID] = section
	}
	notes := make(map[string]struct{}, len(board.Notes))
	for _, placement := range board.Notes {
		if !validID(placement.NoteID) {
			return fmt.Errorf("invalid note id %q", placement.NoteID)
		}
		if _, exists := notes[placement.NoteID]; exists {
			return fmt.Errorf("duplicate note layout %q", placement.NoteID)
		}
		section, exists := sections[placement.SectionID]
		if !exists {
			return fmt.Errorf("note %s references unknown section %s", placement.NoteID, placement.SectionID)
		}
		if err := validateNoteFrame(placement.Frame, section.Frame); err != nil {
			return fmt.Errorf("note %s: %w", placement.NoteID, err)
		}
		notes[placement.NoteID] = struct{}{}
	}
	return nil
}

func validateNote(note Note, archived bool) error {
	if !validID(note.ID) {
		return fmt.Errorf("invalid note id %q", note.ID)
	}
	if err := validateTitle(note.Title, "note"); err != nil {
		return err
	}
	if len(note.Description) > MaxDescriptionBytes {
		return fmt.Errorf("note description exceeds the %d-byte limit", MaxDescriptionBytes)
	}
	if !utf8.ValidString(note.Description) || strings.ContainsRune(note.Description, '\x00') {
		return errors.New("note description must be valid UTF-8 without NUL bytes")
	}
	if note.CreatedAt.IsZero() || note.UpdatedAt.IsZero() || note.UpdatedAt.Before(note.CreatedAt) {
		return errors.New("note timestamps are invalid")
	}
	if note.ForkedFrom != "" && !validID(note.ForkedFrom) {
		return fmt.Errorf("invalid fork source id %q", note.ForkedFrom)
	}
	if archived {
		if note.ArchivedAt == nil || note.ArchivedAt.IsZero() || note.ArchivedAt.Before(note.UpdatedAt) ||
			!validID(note.ArchivedFromSectionID) {
			return errors.New("archived note metadata is incomplete")
		}
		if err := validateTitle(note.ArchivedFromSectionTitle, "archived section"); err != nil {
			return err
		}
	} else if note.ArchivedAt != nil || note.ArchivedFromSectionID != "" || note.ArchivedFromSectionTitle != "" {
		return errors.New("active note contains archive metadata")
	}
	return nil
}

func validateTitle(title, kind string) error {
	trimmed := strings.TrimSpace(title)
	if trimmed == "" || trimmed != title {
		return fmt.Errorf("%s title must be nonempty and trimmed", kind)
	}
	if len(title) > MaxTitleBytes || !utf8.ValidString(title) || strings.ContainsAny(title, "\r\n\x00") {
		return fmt.Errorf("%s title must be one valid UTF-8 line of at most %d bytes", kind, MaxTitleBytes)
	}
	return nil
}

func validateSectionFrame(frame Frame, board Size) error {
	if !validDimension(frame.Width, MinimumSectionWidth, MaximumSectionWidth) ||
		!validDimension(frame.Height, MinimumSectionHeight, MaximumSectionHeight) ||
		!finite(frame.X) || !finite(frame.Y) || frame.X < 0 || frame.Y < 0 ||
		frame.X+frame.Width > board.Width || frame.Y+frame.Height > board.Height {
		return errors.New("frame is outside pinboard bounds")
	}
	return nil
}

func validateNoteFrame(frame Frame, section Frame) error {
	contentHeight := section.Height - SectionHeaderHeight
	if !approximately(frame.Width, NoteWidth) || !approximately(frame.Height, NoteHeight) ||
		!finite(frame.X) || !finite(frame.Y) || frame.X < 0 || frame.Y < 0 ||
		frame.X+frame.Width > section.Width || frame.Y+frame.Height > contentHeight {
		return errors.New("frame is outside section content bounds")
	}
	return nil
}

func clampNoteFrame(frame Frame, section Frame) Frame {
	frame.Width, frame.Height = NoteWidth, NoteHeight
	frame.X = min(max(finiteOrZero(frame.X), 0), max(section.Width-NoteWidth, 0))
	frame.Y = min(max(finiteOrZero(frame.Y), 0), max(section.Height-SectionHeaderHeight-NoteHeight, 0))
	return frame
}

func validID(id string) bool    { return opaqueIDPattern.MatchString(id) }
func finite(value float64) bool { return !math.IsNaN(value) && !math.IsInf(value, 0) }
func finiteOrZero(value float64) float64 {
	if finite(value) {
		return value
	}
	return 0
}
func validDimension(value, minimum, maximum float64) bool {
	return finite(value) && value >= minimum && value <= maximum
}
func approximately(lhs, rhs float64) bool { return math.Abs(lhs-rhs) < 0.001 }
