package notepad

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unicode/utf8"
)

func loadDocument(path string, kind Kind, date string) (Document, error) {
	document := Document{
		Kind: kind, Date: date, Filename: filepath.Base(path), Path: path,
	}
	entry, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return document, nil
	}
	if err != nil {
		return Document{}, fmt.Errorf("inspect note %s: %w", path, err)
	}
	if entry.Mode()&os.ModeSymlink != 0 || !entry.Mode().IsRegular() {
		return Document{}, fmt.Errorf("note must be a regular file: %s", path)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		return Document{}, fmt.Errorf("secure note %s: %w", path, err)
	}
	if err := os.Chmod(filepath.Dir(path), 0o700); err != nil {
		return Document{}, fmt.Errorf("secure notes directory: %w", err)
	}
	file, err := os.Open(path)
	if err != nil {
		return Document{}, fmt.Errorf("open note %s: %w", path, err)
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, MaxBytes+1))
	if err != nil {
		return Document{}, fmt.Errorf("read note %s: %w", path, err)
	}
	if err := validateContent(string(contents)); err != nil {
		return Document{}, fmt.Errorf("read note %s: %w", path, err)
	}
	info, err := file.Stat()
	if err != nil {
		return Document{}, fmt.Errorf("inspect note %s: %w", path, err)
	}
	document.Content = string(contents)
	document.UpdatedAt = info.ModTime().UTC()
	document.Exists = true
	return document, nil
}

func writeDocument(path string, kind Kind, date, content string) (document Document, returnErr error) {
	directory := filepath.Dir(path)
	if err := secureDirectory(directory); err != nil {
		return Document{}, err
	}
	file, err := os.CreateTemp(directory, ".hyperlite-note-*.md")
	if err != nil {
		return Document{}, fmt.Errorf("create temporary note: %w", err)
	}
	temporary := file.Name()
	defer func() {
		if err := os.Remove(temporary); err != nil &&
			!errors.Is(err, os.ErrNotExist) && returnErr == nil {
			returnErr = fmt.Errorf("remove temporary note %s: %w", temporary, err)
		}
	}()
	if err := file.Chmod(0o600); err != nil {
		_ = file.Close()
		return Document{}, fmt.Errorf("secure temporary note: %w", err)
	}
	if _, err := io.WriteString(file, content); err != nil {
		_ = file.Close()
		return Document{}, fmt.Errorf("write temporary note: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return Document{}, fmt.Errorf("sync temporary note: %w", err)
	}
	if err := file.Close(); err != nil {
		return Document{}, fmt.Errorf("close temporary note: %w", err)
	}
	if err := os.Rename(temporary, path); err != nil {
		return Document{}, fmt.Errorf("replace note %s: %w", path, err)
	}
	if err := syncDirectory(directory); err != nil {
		return Document{}, err
	}
	return loadDocument(path, kind, date)
}

func adoptLegacyDocument(legacy, pinned string) error {
	document, err := loadDocument(legacy, KindPinned, "")
	if err != nil {
		return fmt.Errorf("adopt legacy notepad: %w", err)
	}
	if !document.Exists {
		return os.ErrNotExist
	}
	if err := secureDirectory(filepath.Dir(pinned)); err != nil {
		return err
	}
	if err := os.Rename(legacy, pinned); err != nil {
		if !errors.Is(err, syscall.EXDEV) {
			return fmt.Errorf("adopt legacy notepad %s as %s: %w", legacy, pinned, err)
		}
		if _, writeErr := writeDocument(pinned, KindPinned, "", document.Content); writeErr != nil {
			return writeErr
		}
		if removeErr := os.Remove(legacy); removeErr != nil {
			return fmt.Errorf("remove adopted legacy notepad %s: %w", legacy, removeErr)
		}
	}
	if err := syncDirectory(filepath.Dir(pinned)); err != nil {
		return err
	}
	if filepath.Dir(legacy) != filepath.Dir(pinned) {
		if err := syncDirectory(filepath.Dir(legacy)); err != nil {
			return err
		}
	}
	return nil
}

func withStoreLock(root string, operation func() error) (returnErr error) {
	if err := secureDirectory(root); err != nil {
		return err
	}
	lockPath := filepath.Join(root, ".hyperlite-notes.lock")
	lock, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return fmt.Errorf("open notes lock: %w", err)
	}
	if err := lock.Chmod(0o600); err != nil {
		_ = lock.Close()
		return fmt.Errorf("secure notes lock: %w", err)
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		_ = lock.Close()
		return fmt.Errorf("lock notes: %w", err)
	}
	defer func() {
		if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_UN); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("unlock notes: %w", err)
		}
		if err := lock.Close(); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("close notes lock: %w", err)
		}
	}()
	return operation()
}

func secureDirectory(directory string) error {
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return fmt.Errorf("create notes directory: %w", err)
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return fmt.Errorf("secure notes directory: %w", err)
	}
	return nil
}

func syncDirectory(directory string) error {
	handle, err := os.Open(directory)
	if err != nil {
		return fmt.Errorf("open notes directory for sync: %w", err)
	}
	if err := handle.Sync(); err != nil {
		_ = handle.Close()
		return fmt.Errorf("sync notes directory: %w", err)
	}
	if err := handle.Close(); err != nil {
		return fmt.Errorf("close notes directory: %w", err)
	}
	return nil
}

func validateContent(content string) error {
	if len(content) > MaxBytes {
		return fmt.Errorf("note exceeds the %d-byte limit", MaxBytes)
	}
	if !utf8.ValidString(content) {
		return errors.New("note must be valid UTF-8")
	}
	if strings.ContainsRune(content, '\x00') {
		return errors.New("note cannot contain NUL bytes")
	}
	return nil
}
