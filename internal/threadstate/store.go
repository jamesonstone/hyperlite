package threadstate

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

var stateMutex sync.Mutex

type Store struct {
	Path string
	Now  func() time.Time
}

func ResolvePath() (string, error) {
	if override := strings.TrimSpace(os.Getenv("HYPERLITE_STATE_PATH")); override != "" {
		return filepath.Abs(override)
	}
	root := os.Getenv("XDG_STATE_HOME")
	if root == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("resolve home directory for thread state: %w", err)
		}
		root = filepath.Join(home, ".local", "state")
	}
	absolute, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve thread state directory: %w", err)
	}
	return filepath.Join(filepath.Clean(absolute), "hyperlite", "threads.json"), nil
}

func (s Store) Load() (State, string, error) {
	stateMutex.Lock()
	defer stateMutex.Unlock()
	return s.load()
}

func (s Store) load() (State, string, error) {
	path, err := s.path()
	if err != nil {
		return State{}, "", err
	}
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return Empty(), "", nil
	}
	if err != nil {
		return State{}, "", fmt.Errorf("open thread state %s: %w", path, err)
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	var state State
	if err := decoder.Decode(&state); err != nil {
		return s.preserveCorrupt(path, fmt.Errorf("decode: %w", err))
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			err = errors.New("trailing JSON is not supported")
		}
		return s.preserveCorrupt(path, err)
	}
	if err := validate(&state); err != nil {
		return s.preserveCorrupt(path, fmt.Errorf("validate: %w", err))
	}
	return state, "", nil
}

func (s Store) preserveCorrupt(path string, cause error) (State, string, error) {
	backup := fmt.Sprintf("%s.corrupt-%s", path, s.now().UTC().Format("20060102T150405Z"))
	if err := os.Rename(path, backup); err != nil {
		return State{}, "", fmt.Errorf("preserve corrupt thread state %s: %w (original: %v)", path, err, cause)
	}
	return Empty(), fmt.Sprintf("preserved corrupt thread state at %s: %v", backup, cause), nil
}

func (s Store) Write(state State) error {
	stateMutex.Lock()
	defer stateMutex.Unlock()
	return s.withFileLock(func() error { return s.write(state) })
}

func (s Store) write(state State) (returnErr error) {
	if err := validate(&state); err != nil {
		return fmt.Errorf("validate thread state: %w", err)
	}
	path, err := s.path()
	if err != nil {
		return err
	}
	state.UpdatedAt = s.now()
	sortState(&state)
	contents, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("encode thread state: %w", err)
	}
	contents = append(contents, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create thread state directory: %w", err)
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".hyperlite-threads-*.json")
	if err != nil {
		return fmt.Errorf("create temporary thread state: %w", err)
	}
	temporary := file.Name()
	defer func() {
		if err := os.Remove(temporary); err != nil && !errors.Is(err, os.ErrNotExist) && returnErr == nil {
			returnErr = fmt.Errorf("remove temporary thread state %s: %w", temporary, err)
		}
	}()
	if err := file.Chmod(0o600); err != nil {
		file.Close()
		return err
	}
	if _, err := file.Write(contents); err != nil {
		file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporary, path); err != nil {
		return fmt.Errorf("replace thread state %s: %w", path, err)
	}
	return nil
}

func (s Store) Mutate(mutate func(*State) error) error {
	stateMutex.Lock()
	defer stateMutex.Unlock()
	return s.withFileLock(func() error {
		state, _, err := s.load()
		if err != nil {
			return err
		}
		if err := mutate(&state); err != nil {
			return err
		}
		return s.write(state)
	})
}

func (s Store) withFileLock(operation func() error) (returnErr error) {
	path, err := s.path()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create thread state directory: %w", err)
	}
	lock, err := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return fmt.Errorf("open thread state lock: %w", err)
	}
	if err := lock.Chmod(0o600); err != nil {
		_ = lock.Close()
		return fmt.Errorf("secure thread state lock: %w", err)
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		_ = lock.Close()
		return fmt.Errorf("lock thread state: %w", err)
	}
	defer func() {
		if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_UN); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("unlock thread state: %w", err)
		}
		if err := lock.Close(); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("close thread state lock: %w", err)
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

func (s Store) now() time.Time {
	if s.Now != nil {
		return s.Now().UTC()
	}
	return time.Now().UTC()
}

func validate(state *State) error {
	if state.Version != Version {
		return fmt.Errorf("version must equal %d", Version)
	}
	if state.Remote == nil {
		state.Remote = map[string]RemoteCache{}
	}
	if state.Threads == nil {
		state.Threads = []ThreadRecord{}
	}
	if state.Inferences == nil {
		state.Inferences = []InferenceRecord{}
	}
	seen := make(map[string]struct{}, len(state.Threads))
	for _, record := range state.Threads {
		if strings.TrimSpace(record.ID) == "" {
			return errors.New("thread id is required")
		}
		if _, exists := seen[record.ID]; exists {
			return fmt.Errorf("duplicate thread id %q", record.ID)
		}
		seen[record.ID] = struct{}{}
	}
	return nil
}

func sortState(state *State) {
	sort.Slice(state.Threads, func(i, j int) bool { return state.Threads[i].ID < state.Threads[j].ID })
	sort.Slice(state.Inferences, func(i, j int) bool {
		if state.Inferences[i].ThreadID != state.Inferences[j].ThreadID {
			return state.Inferences[i].ThreadID < state.Inferences[j].ThreadID
		}
		return state.Inferences[i].Digest < state.Inferences[j].Digest
	})
}
