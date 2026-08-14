package pinboard

import "time"

const (
	SchemaVersion        = 1
	DefaultBoardWidth    = 1600.0
	DefaultBoardHeight   = 1000.0
	SectionHeaderHeight  = 36.0
	DefaultSectionWidth  = 320.0
	DefaultSectionHeight = 560.0
	MinimumSectionWidth  = 260.0
	MinimumSectionHeight = 300.0
	MaximumSectionWidth  = 700.0
	MaximumSectionHeight = 950.0
	NoteWidth            = 220.0
	NoteHeight           = 150.0
	CascadeOffset        = 18.0
	MaxSections          = 64
	MaxActiveNotes       = 2048
	MaxArchivedNotes     = 4096
	MaxTitleBytes        = 256
	MaxDescriptionBytes  = 256 * 1024
	MaxLayoutBytes       = 2 * 1024 * 1024
	MaxMutationBytes     = MaxDescriptionBytes + 16*1024
)

type Size struct {
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

type Frame struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

type Section struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Frame Frame  `json:"frame"`
}

type NoteLayout struct {
	NoteID    string `json:"note_id"`
	SectionID string `json:"section_id"`
	Frame     Frame  `json:"frame"`
}

type Board struct {
	SchemaVersion int          `json:"schema_version"`
	Size          Size         `json:"size"`
	Sections      []Section    `json:"sections"`
	Notes         []NoteLayout `json:"notes"`
}

type Note struct {
	ID                       string     `json:"id" yaml:"id"`
	Title                    string     `json:"title" yaml:"title"`
	Description              string     `json:"description" yaml:"-"`
	CreatedAt                time.Time  `json:"created_at" yaml:"created_at"`
	UpdatedAt                time.Time  `json:"updated_at" yaml:"updated_at"`
	ForkedFrom               string     `json:"forked_from,omitempty" yaml:"forked_from,omitempty"`
	ArchivedAt               *time.Time `json:"archived_at,omitempty" yaml:"archived_at,omitempty"`
	ArchivedFromSectionID    string     `json:"archived_from_section_id,omitempty" yaml:"archived_from_section_id,omitempty"`
	ArchivedFromSectionTitle string     `json:"archived_from_section_title,omitempty" yaml:"archived_from_section_title,omitempty"`
}

type Snapshot struct {
	Board   Board  `json:"board"`
	Notes   []Note `json:"notes"`
	Archive []Note `json:"archive"`
}

type MutationKind string

const (
	MutationAddSection         MutationKind = "add_section"
	MutationRenameSection      MutationKind = "rename_section"
	MutationUpdateSectionFrame MutationKind = "update_section_frame"
	MutationDeleteSection      MutationKind = "delete_section"
	MutationAddNote            MutationKind = "add_note"
	MutationUpdateNote         MutationKind = "update_note"
	MutationMoveNote           MutationKind = "move_note"
	MutationForkNote           MutationKind = "fork_note"
	MutationArchiveNote        MutationKind = "archive_note"
	MutationRestoreNote        MutationKind = "restore_note"
)

type Mutation struct {
	Kind         MutationKind `json:"kind"`
	SectionID    string       `json:"section_id,omitempty"`
	NoteID       string       `json:"note_id,omitempty"`
	Title        string       `json:"title,omitempty"`
	Description  string       `json:"description,omitempty"`
	Frame        *Frame       `json:"frame,omitempty"`
	ArchiveNotes bool         `json:"archive_notes,omitempty"`
}

func NewBoard() Board {
	return Board{
		SchemaVersion: SchemaVersion,
		Size:          Size{Width: DefaultBoardWidth, Height: DefaultBoardHeight},
		Sections:      []Section{}, Notes: []NoteLayout{},
	}
}
