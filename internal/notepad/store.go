package notepad

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const MaxBytes = 256 * 1024

const (
	pinnedFileName     = "pinned.md"
	dailyDirectoryName = "daily"
	dateLayout         = "2006-01-02"
	legacyTextFileName = "notepad.txt"
	legacyMarkdownName = "notepad.md"
	notesOverrideEnv   = "HYPERLITE_NOTES_PATH"
	legacyOverrideEnv  = "HYPERLITE_NOTEPAD_PATH"
)

type Kind string

const (
	KindPinned Kind = "pinned"
	KindDaily  Kind = "daily"
)

type Document struct {
	Kind      Kind      `json:"kind"`
	Date      string    `json:"date,omitempty"`
	Filename  string    `json:"filename"`
	Content   string    `json:"content"`
	Path      string    `json:"path"`
	UpdatedAt time.Time `json:"updated_at,omitzero"`
	Exists    bool      `json:"exists"`
}

type Store struct {
	Root       string
	LegacyPath string
}

var storeMutex sync.Mutex

func ResolveRoot() (string, error) {
	if override := strings.TrimSpace(os.Getenv(notesOverrideEnv)); override != "" {
		return filepath.Abs(override)
	}
	if legacy := strings.TrimSpace(os.Getenv(legacyOverrideEnv)); legacy != "" {
		absolute, err := filepath.Abs(legacy)
		if err != nil {
			return "", fmt.Errorf("resolve legacy notepad path: %w", err)
		}
		return filepath.Join(filepath.Dir(absolute), "notes"), nil
	}
	root := os.Getenv("XDG_DATA_HOME")
	if root == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("resolve home directory for notes: %w", err)
		}
		root = filepath.Join(home, ".local", "share")
	}
	absolute, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve notes data directory: %w", err)
	}
	return filepath.Join(filepath.Clean(absolute), "hyperlite", "notes"), nil
}

func ResolvePinnedPath() (string, error) {
	root, err := ResolveRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(root, pinnedFileName), nil
}

func (s Store) LoadPinned() (Document, error) {
	return s.read(KindPinned, "")
}

func (s Store) LoadDaily(date string) (Document, error) {
	if err := validateDate(date); err != nil {
		return Document{}, err
	}
	return s.read(KindDaily, date)
}

func (s Store) WritePinned(content string) (Document, error) {
	return s.write(KindPinned, "", content)
}

func (s Store) WriteDaily(date, content string) (Document, error) {
	if err := validateDate(date); err != nil {
		return Document{}, err
	}
	return s.write(KindDaily, date, content)
}

func (s Store) Path(date string) (string, error) {
	if date != "" {
		if err := validateDate(date); err != nil {
			return "", err
		}
	}
	root, err := s.root()
	if err != nil {
		return "", err
	}
	return documentPath(root, kindForDate(date), date), nil
}

func (s Store) Documents() ([]Document, error) {
	storeMutex.Lock()
	defer storeMutex.Unlock()
	root, err := s.root()
	if err != nil {
		return nil, err
	}
	var documents []Document
	err = withStoreLock(root, func() error {
		if err := s.migrateLegacy(root); err != nil {
			return err
		}
		pinned, err := loadDocument(documentPath(root, KindPinned, ""), KindPinned, "")
		if err != nil {
			return err
		}
		documents = append(documents, pinned)
		daily, err := loadDailyDocuments(root)
		if err != nil {
			return err
		}
		documents = append(documents, daily...)
		return nil
	})
	return documents, err
}

func (s Store) read(kind Kind, date string) (Document, error) {
	storeMutex.Lock()
	defer storeMutex.Unlock()
	root, err := s.root()
	if err != nil {
		return Document{}, err
	}
	var document Document
	err = withStoreLock(root, func() error {
		if kind == KindPinned {
			if err := s.migrateLegacy(root); err != nil {
				return err
			}
		}
		var loadErr error
		document, loadErr = loadDocument(documentPath(root, kind, date), kind, date)
		return loadErr
	})
	return document, err
}

func (s Store) write(kind Kind, date, content string) (Document, error) {
	if err := validateContent(content); err != nil {
		return Document{}, err
	}
	storeMutex.Lock()
	defer storeMutex.Unlock()
	root, err := s.root()
	if err != nil {
		return Document{}, err
	}
	var document Document
	err = withStoreLock(root, func() error {
		if kind == KindPinned {
			if err := s.migrateLegacy(root); err != nil {
				return err
			}
		}
		var writeErr error
		document, writeErr = writeDocument(documentPath(root, kind, date), kind, date, content)
		return writeErr
	})
	return document, err
}

func (s Store) root() (string, error) {
	if s.Root != "" {
		return filepath.Abs(s.Root)
	}
	return ResolveRoot()
}

func (s Store) migrateLegacy(root string) error {
	pinned := documentPath(root, KindPinned, "")
	if _, err := os.Lstat(pinned); err == nil {
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect pinned note %s: %w", pinned, err)
	}
	for _, legacy := range s.legacyPaths(root) {
		if err := adoptLegacyDocument(legacy, pinned); errors.Is(err, os.ErrNotExist) {
			continue
		} else if err != nil {
			return err
		}
		return nil
	}
	return nil
}

func (s Store) legacyPaths(root string) []string {
	if s.LegacyPath != "" {
		absolute, err := filepath.Abs(s.LegacyPath)
		if err == nil {
			return []string{absolute}
		}
		return []string{s.LegacyPath}
	}
	if s.Root != "" || strings.TrimSpace(os.Getenv(notesOverrideEnv)) != "" {
		return nil
	}
	if override := strings.TrimSpace(os.Getenv(legacyOverrideEnv)); override != "" {
		absolute, err := filepath.Abs(override)
		if err == nil {
			return []string{absolute}
		}
		return []string{override}
	}
	parent := filepath.Dir(root)
	return []string{
		filepath.Join(parent, legacyTextFileName),
		filepath.Join(parent, legacyMarkdownName),
	}
}

func loadDailyDocuments(root string) ([]Document, error) {
	directory := filepath.Join(root, dailyDirectoryName)
	entries, err := os.ReadDir(directory)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("list daily notes: %w", err)
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return nil, fmt.Errorf("secure daily notes directory: %w", err)
	}
	documents := make([]Document, 0, len(entries))
	for _, entry := range entries {
		date, ok := dateFromFilename(entry.Name())
		if !ok || !entry.Type().IsRegular() {
			continue
		}
		document, err := loadDocument(filepath.Join(directory, entry.Name()), KindDaily, date)
		if err != nil {
			continue
		}
		documents = append(documents, document)
	}
	sort.Slice(documents, func(i, j int) bool { return documents[i].Date > documents[j].Date })
	return documents, nil
}

func documentPath(root string, kind Kind, date string) string {
	if kind == KindDaily {
		return filepath.Join(root, dailyDirectoryName, date+".md")
	}
	return filepath.Join(root, pinnedFileName)
}

func kindForDate(date string) Kind {
	if date == "" {
		return KindPinned
	}
	return KindDaily
}

func dateFromFilename(filename string) (string, bool) {
	if filepath.Ext(filename) != ".md" {
		return "", false
	}
	date := strings.TrimSuffix(filename, ".md")
	return date, validateDate(date) == nil
}

func validateDate(date string) error {
	parsed, err := time.Parse(dateLayout, date)
	if err != nil || parsed.Format(dateLayout) != date {
		return fmt.Errorf("daily note date must use YYYY-MM-DD: %q", date)
	}
	return nil
}
