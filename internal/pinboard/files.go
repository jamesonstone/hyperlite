package pinboard

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
)

const (
	rootOverrideEnv  = "HYPERLITE_PINBOARD_PATH"
	boardFileName    = "board.json"
	notesDirectory   = "notes"
	archiveDirectory = "archive"
	lockFileName     = ".hyperlite-pinboard.lock"
	timeFormat       = "2006-01-02T15:04:05.999999999Z07:00"
)

var processMutex sync.Mutex

func ResolveRoot() (string, error) {
	if override := strings.TrimSpace(os.Getenv(rootOverrideEnv)); override != "" {
		return filepath.Abs(override)
	}
	dataRoot := strings.TrimSpace(os.Getenv("XDG_DATA_HOME"))
	if dataRoot == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("resolve home directory for pinboard: %w", err)
		}
		dataRoot = filepath.Join(home, ".local", "share")
	}
	absolute, err := filepath.Abs(dataRoot)
	if err != nil {
		return "", fmt.Errorf("resolve pinboard data directory: %w", err)
	}
	return filepath.Join(filepath.Clean(absolute), "hyperlite", "board"), nil
}

func withLock(root string, operation func() error) (returnErr error) {
	processMutex.Lock()
	defer processMutex.Unlock()
	if err := secureDirectory(root); err != nil {
		return err
	}
	lockPath := filepath.Join(root, lockFileName)
	lock, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return fmt.Errorf("open pinboard lock: %w", err)
	}
	if err := lock.Chmod(0o600); err != nil {
		_ = lock.Close()
		return fmt.Errorf("secure pinboard lock: %w", err)
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		_ = lock.Close()
		return fmt.Errorf("lock pinboard: %w", err)
	}
	defer func() {
		if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_UN); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("unlock pinboard: %w", err)
		}
		if err := lock.Close(); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("close pinboard lock: %w", err)
		}
	}()
	return operation()
}

func loadBoard(root string) (Board, error) {
	path := filepath.Join(root, boardFileName)
	contents, exists, err := readRegular(path, MaxLayoutBytes)
	if err != nil {
		return Board{}, err
	}
	if !exists {
		return NewBoard(), nil
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var board Board
	if err := decoder.Decode(&board); err != nil {
		return Board{}, fmt.Errorf("decode pinboard layout: %w", err)
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return Board{}, errors.New("pinboard layout contains multiple JSON values")
		}
		return Board{}, fmt.Errorf("decode pinboard layout: %w", err)
	}
	if err := validateBoard(board); err != nil {
		return Board{}, fmt.Errorf("validate pinboard layout: %w", err)
	}
	return board, nil
}

func writeBoard(root string, board Board) error {
	if err := validateBoard(board); err != nil {
		return err
	}
	contents, err := json.MarshalIndent(board, "", "  ")
	if err != nil {
		return fmt.Errorf("encode pinboard layout: %w", err)
	}
	contents = append(contents, '\n')
	if len(contents) > MaxLayoutBytes {
		return errors.New("pinboard layout exceeds supported size")
	}
	return writeAtomic(filepath.Join(root, boardFileName), contents)
}

func loadNoteFile(root, id string, archived bool) (Note, error) {
	if !validID(id) {
		return Note{}, fmt.Errorf("invalid note id %q", id)
	}
	directory := notesDirectory
	if archived {
		directory = archiveDirectory
	}
	path := filepath.Join(root, directory, id+".md")
	contents, exists, err := readRegular(path, MaxMutationBytes)
	if err != nil {
		return Note{}, err
	}
	if !exists {
		return Note{}, fmt.Errorf("note %s is missing", id)
	}
	note, err := decodeNote(contents, archived)
	if err != nil {
		return Note{}, fmt.Errorf("decode note %s: %w", id, err)
	}
	if note.ID != id {
		return Note{}, fmt.Errorf("note filename id %s does not match metadata id %s", id, note.ID)
	}
	return note, nil
}

func writeNoteFile(root string, note Note, archived bool, requireAbsent bool) error {
	contents, err := encodeNote(note, archived)
	if err != nil {
		return err
	}
	directory := notesDirectory
	if archived {
		directory = archiveDirectory
	}
	path := filepath.Join(root, directory, note.ID+".md")
	if requireAbsent {
		if _, err := os.Lstat(path); err == nil {
			return fmt.Errorf("note %s already exists", note.ID)
		} else if !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	return writeAtomic(path, contents)
}

func removeNoteFile(root, id string, archived bool) error {
	directory := notesDirectory
	if archived {
		directory = archiveDirectory
	}
	path := filepath.Join(root, directory, id+".md")
	if err := os.Remove(path); err != nil {
		return fmt.Errorf("remove note %s: %w", id, err)
	}
	return syncDirectory(filepath.Dir(path))
}

func readRegular(path string, limit int64) ([]byte, bool, error) {
	entry, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, fmt.Errorf("inspect %s: %w", path, err)
	}
	if entry.Mode()&os.ModeSymlink != 0 || !entry.Mode().IsRegular() {
		return nil, false, fmt.Errorf("pinboard source must be a regular file: %s", path)
	}
	if entry.Size() > limit {
		return nil, false, fmt.Errorf("pinboard source exceeds %d-byte limit: %s", limit, path)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		return nil, false, fmt.Errorf("secure %s: %w", path, err)
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, false, fmt.Errorf("open %s: %w", path, err)
	}
	defer func() { _ = file.Close() }()
	contents, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err != nil {
		return nil, false, fmt.Errorf("read %s: %w", path, err)
	}
	if int64(len(contents)) > limit {
		return nil, false, fmt.Errorf("pinboard source exceeds %d-byte limit: %s", limit, path)
	}
	return contents, true, nil
}

func writeAtomic(path string, contents []byte) (returnErr error) {
	directory := filepath.Dir(path)
	if err := secureDirectory(directory); err != nil {
		return err
	}
	file, err := os.CreateTemp(directory, ".hyperlite-pinboard-*")
	if err != nil {
		return fmt.Errorf("create temporary pinboard file: %w", err)
	}
	temporary := file.Name()
	defer func() {
		if err := os.Remove(temporary); err != nil && !errors.Is(err, os.ErrNotExist) && returnErr == nil {
			returnErr = err
		}
	}()
	if err := file.Chmod(0o600); err != nil {
		_ = file.Close()
		return err
	}
	written, err := file.Write(contents)
	if err != nil {
		_ = file.Close()
		return err
	}
	if written != len(contents) {
		_ = file.Close()
		return io.ErrShortWrite
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporary, path); err != nil {
		return fmt.Errorf("replace %s: %w", path, err)
	}
	return syncDirectory(directory)
}

func secureDirectory(directory string) error {
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return fmt.Errorf("create pinboard directory: %w", err)
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return fmt.Errorf("secure pinboard directory: %w", err)
	}
	return nil
}

func syncDirectory(directory string) error {
	handle, err := os.Open(directory)
	if err != nil {
		return fmt.Errorf("open pinboard directory for sync: %w", err)
	}
	if err := handle.Sync(); err != nil {
		_ = handle.Close()
		return fmt.Errorf("sync pinboard directory: %w", err)
	}
	if err := handle.Close(); err != nil {
		return fmt.Errorf("close pinboard directory: %w", err)
	}
	return nil
}
