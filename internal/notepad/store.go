package notepad

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

const MaxBytes = 256 * 1024

const (
	notepadFileName       = "notepad.txt"
	legacyNotepadFileName = "notepad.md"
)

type Document struct {
	Content   string    `json:"content"`
	Path      string    `json:"path"`
	UpdatedAt time.Time `json:"updated_at,omitzero"`
}

type Store struct {
	Path string
}

var storeMutex sync.Mutex

func ResolvePath() (string, error) {
	if override := strings.TrimSpace(os.Getenv("HYPERLITE_NOTEPAD_PATH")); override != "" {
		return filepath.Abs(override)
	}
	root := os.Getenv("XDG_DATA_HOME")
	if root == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("resolve home directory for notepad: %w", err)
		}
		root = filepath.Join(home, ".local", "share")
	}
	absolute, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve notepad data directory: %w", err)
	}
	return filepath.Join(filepath.Clean(absolute), "hyperlite", notepadFileName), nil
}

func (s Store) Load() (Document, error) {
	storeMutex.Lock()
	defer storeMutex.Unlock()
	path, err := s.path()
	if err != nil {
		return Document{}, err
	}
	if legacy := s.legacyPath(path); legacy != "" {
		if err := withFileLock(path, func() error {
			return migrateLegacyDocument(legacy, path)
		}); err != nil {
			return Document{}, err
		}
	}
	return load(path)
}

func (s Store) Write(content string) (Document, error) {
	storeMutex.Lock()
	defer storeMutex.Unlock()
	if err := validate(content); err != nil {
		return Document{}, err
	}
	path, err := s.path()
	if err != nil {
		return Document{}, err
	}
	var document Document
	err = withFileLock(path, func() error {
		var writeErr error
		document, writeErr = write(path, content)
		return writeErr
	})
	return document, err
}

func load(path string) (Document, error) {
	entry, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return Document{Path: path}, nil
	}
	if err != nil {
		return Document{}, fmt.Errorf("inspect notepad %s: %w", path, err)
	}
	if entry.Mode()&os.ModeSymlink != 0 || !entry.Mode().IsRegular() {
		return Document{}, fmt.Errorf("notepad must be a regular file: %s", path)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		return Document{}, fmt.Errorf("secure notepad %s: %w", path, err)
	}
	if err := os.Chmod(filepath.Dir(path), 0o700); err != nil {
		return Document{}, fmt.Errorf("secure notepad directory: %w", err)
	}
	file, err := os.Open(path)
	if err != nil {
		return Document{}, fmt.Errorf("open notepad %s: %w", path, err)
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, MaxBytes+1))
	if err != nil {
		return Document{}, fmt.Errorf("read notepad %s: %w", path, err)
	}
	if len(contents) > MaxBytes {
		return Document{}, fmt.Errorf("notepad exceeds the %d-byte limit", MaxBytes)
	}
	info, err := file.Stat()
	if err != nil {
		return Document{}, fmt.Errorf("inspect notepad %s: %w", path, err)
	}
	return Document{Content: string(contents), Path: path, UpdatedAt: info.ModTime().UTC()}, nil
}

func write(path, content string) (document Document, returnErr error) {
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return Document{}, fmt.Errorf("create notepad directory: %w", err)
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return Document{}, fmt.Errorf("secure notepad directory: %w", err)
	}
	file, err := os.CreateTemp(directory, ".hyperlite-notepad-*.txt")
	if err != nil {
		return Document{}, fmt.Errorf("create temporary notepad: %w", err)
	}
	temporary := file.Name()
	defer func() {
		if err := os.Remove(temporary); err != nil &&
			!errors.Is(err, os.ErrNotExist) && returnErr == nil {
			returnErr = fmt.Errorf("remove temporary notepad %s: %w", temporary, err)
		}
	}()
	if err := file.Chmod(0o600); err != nil {
		_ = file.Close()
		return Document{}, fmt.Errorf("secure temporary notepad: %w", err)
	}
	if _, err := io.WriteString(file, content); err != nil {
		_ = file.Close()
		return Document{}, fmt.Errorf("write temporary notepad: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return Document{}, fmt.Errorf("sync temporary notepad: %w", err)
	}
	if err := file.Close(); err != nil {
		return Document{}, fmt.Errorf("close temporary notepad: %w", err)
	}
	if err := os.Rename(temporary, path); err != nil {
		return Document{}, fmt.Errorf("replace notepad %s: %w", path, err)
	}
	if err := syncDirectory(directory); err != nil {
		return Document{}, err
	}
	return load(path)
}

func migrateLegacyDocument(legacy, current string) error {
	if _, err := os.Lstat(current); err == nil {
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect notepad %s: %w", current, err)
	}
	if _, err := load(legacy); errors.Is(err, os.ErrNotExist) {
		return nil
	} else if err != nil {
		return fmt.Errorf("migrate legacy notepad: %w", err)
	}
	if err := os.Rename(legacy, current); err != nil {
		return fmt.Errorf("migrate legacy notepad %s to %s: %w", legacy, current, err)
	}
	return syncDirectory(filepath.Dir(current))
}

func syncDirectory(directory string) error {
	handle, err := os.Open(directory)
	if err != nil {
		return fmt.Errorf("open notepad directory for sync: %w", err)
	}
	if err := handle.Sync(); err != nil {
		_ = handle.Close()
		return fmt.Errorf("sync notepad directory: %w", err)
	}
	if err := handle.Close(); err != nil {
		return fmt.Errorf("close notepad directory: %w", err)
	}
	return nil
}

func withFileLock(path string, operation func() error) (returnErr error) {
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return fmt.Errorf("create notepad directory: %w", err)
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return fmt.Errorf("secure notepad directory: %w", err)
	}
	lock, err := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return fmt.Errorf("open notepad lock: %w", err)
	}
	if err := lock.Chmod(0o600); err != nil {
		_ = lock.Close()
		return fmt.Errorf("secure notepad lock: %w", err)
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		_ = lock.Close()
		return fmt.Errorf("lock notepad: %w", err)
	}
	defer func() {
		if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_UN); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("unlock notepad: %w", err)
		}
		if err := lock.Close(); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("close notepad lock: %w", err)
		}
	}()
	return operation()
}

func (s Store) path() (string, error) {
	if s.Path != "" {
		return filepath.Abs(s.Path)
	}
	return ResolvePath()
}

func (s Store) legacyPath(current string) string {
	if s.Path != "" || strings.TrimSpace(os.Getenv("HYPERLITE_NOTEPAD_PATH")) != "" {
		return ""
	}
	return filepath.Join(filepath.Dir(current), legacyNotepadFileName)
}

func validate(content string) error {
	if len(content) > MaxBytes {
		return fmt.Errorf("notepad exceeds the %d-byte limit", MaxBytes)
	}
	if strings.ContainsRune(content, '\x00') {
		return errors.New("notepad cannot contain NUL bytes")
	}
	return nil
}
