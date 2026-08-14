package pinboard

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func loadArchive(root string, activePlacements map[string]struct{}) ([]Note, error) {
	ids, err := listNoteIDs(root, archiveDirectory, MaxArchivedNotes)
	if err != nil {
		return nil, err
	}
	notes := make([]Note, 0, len(ids))
	for _, id := range ids {
		if _, active := activePlacements[id]; active {
			continue
		}
		note, loadErr := loadNoteFile(root, id, true)
		if loadErr != nil {
			return nil, loadErr
		}
		notes = append(notes, note)
	}
	sort.Slice(notes, func(i, j int) bool {
		if notes[i].ArchivedAt.Equal(*notes[j].ArchivedAt) {
			return notes[i].ID < notes[j].ID
		}
		return notes[i].ArchivedAt.After(*notes[j].ArchivedAt)
	})
	return notes, nil
}

func listNoteIDs(root, name string, limit int) ([]string, error) {
	directory := filepath.Join(root, name)
	entries, err := os.ReadDir(directory)
	if errors.Is(err, os.ErrNotExist) {
		return []string{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("list pinboard %s: %w", name, err)
	}
	ids := make([]string, 0, len(entries))
	for _, entry := range entries {
		if filepath.Ext(entry.Name()) != ".md" {
			continue
		}
		id := strings.TrimSuffix(entry.Name(), ".md")
		if !validID(id) {
			return nil, fmt.Errorf("pinboard %s contains an invalid note filename %q", name, entry.Name())
		}
		ids = append(ids, id)
	}
	if len(ids) > limit {
		return nil, fmt.Errorf("pinboard %s exceeds supported item count", name)
	}
	sort.Strings(ids)
	return ids, nil
}
