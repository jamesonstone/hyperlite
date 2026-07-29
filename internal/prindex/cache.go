package prindex

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

	"github.com/jamesonstone/hyperlite/internal/model"
)

const cacheVersion = 1

var cacheMutex sync.Mutex

type cacheEntry struct {
	Repository   string                     `json:"repository"`
	CheckedAt    time.Time                  `json:"checked_at,omitempty"`
	ObservedAt   time.Time                  `json:"observed_at"`
	LastError    string                     `json:"last_error,omitempty"`
	PullRequests []model.ProjectPullRequest `json:"pull_requests"`
}

type cacheState struct {
	Version      int                   `json:"version"`
	Projects     map[string]string     `json:"projects"`
	Repositories map[string]cacheEntry `json:"repositories"`
	UpdatedAt    time.Time             `json:"updated_at"`
}

type CacheStore interface {
	Load() (cacheState, string, error)
	Update(func(*cacheState)) (cacheState, error)
}

type Store struct {
	Path string
	Now  func() time.Time
}

func emptyCache() cacheState {
	return cacheState{
		Version: cacheVersion, Projects: map[string]string{},
		Repositories: map[string]cacheEntry{},
	}
}

func ResolveCachePath() (string, error) {
	if override := strings.TrimSpace(os.Getenv("HYPERLITE_PULL_REQUEST_CACHE_PATH")); override != "" {
		return filepath.Abs(override)
	}
	root := os.Getenv("XDG_STATE_HOME")
	if root == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("resolve home directory for pull request cache: %w", err)
		}
		root = filepath.Join(home, ".local", "state")
	}
	absolute, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve pull request cache directory: %w", err)
	}
	return filepath.Join(filepath.Clean(absolute), "hyperlite", "pull-requests.json"), nil
}

func (s Store) Load() (cacheState, string, error) {
	cacheMutex.Lock()
	defer cacheMutex.Unlock()
	var state cacheState
	var warning string
	err := s.withFileLock(func() error {
		var err error
		state, warning, err = s.load()
		return err
	})
	return state, warning, err
}

func (s Store) Update(mutate func(*cacheState)) (cacheState, error) {
	cacheMutex.Lock()
	defer cacheMutex.Unlock()
	var updated cacheState
	err := s.withFileLock(func() error {
		state, _, err := s.load()
		if err != nil {
			return err
		}
		mutate(&state)
		state.UpdatedAt = s.now()
		if err := s.write(state); err != nil {
			return err
		}
		updated = state
		return nil
	})
	return updated, err
}

func (s Store) load() (cacheState, string, error) {
	path, err := s.path()
	if err != nil {
		return cacheState{}, "", err
	}
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return emptyCache(), "", nil
	}
	if err != nil {
		return cacheState{}, "", fmt.Errorf("open pull request cache %s: %w", path, err)
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	var state cacheState
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
	if err := validateCache(&state); err != nil {
		return s.preserveCorrupt(path, fmt.Errorf("validate: %w", err))
	}
	return state, "", nil
}

func (s Store) preserveCorrupt(path string, cause error) (cacheState, string, error) {
	backup := fmt.Sprintf("%s.corrupt-%s", path, s.now().Format("20060102T150405Z"))
	if err := os.Rename(path, backup); err != nil {
		return cacheState{}, "", fmt.Errorf(
			"preserve corrupt pull request cache %s: %w (original: %v)",
			path, err, cause,
		)
	}
	return emptyCache(), fmt.Sprintf(
		"preserved corrupt pull request cache at %s: %v", backup, cause,
	), nil
}

func (s Store) write(state cacheState) (returnErr error) {
	if err := validateCache(&state); err != nil {
		return fmt.Errorf("validate pull request cache: %w", err)
	}
	path, err := s.path()
	if err != nil {
		return err
	}
	sortCache(&state)
	contents, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("encode pull request cache: %w", err)
	}
	contents = append(contents, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create pull request cache directory: %w", err)
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".hyperlite-pull-requests-*.json")
	if err != nil {
		return fmt.Errorf("create temporary pull request cache: %w", err)
	}
	temporary := file.Name()
	defer func() {
		if err := os.Remove(temporary); err != nil &&
			!errors.Is(err, os.ErrNotExist) && returnErr == nil {
			returnErr = fmt.Errorf("remove temporary pull request cache %s: %w", temporary, err)
		}
	}()
	if err := file.Chmod(0o600); err != nil {
		_ = file.Close()
		return err
	}
	if _, err := file.Write(contents); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporary, path); err != nil {
		return fmt.Errorf("replace pull request cache %s: %w", path, err)
	}
	return nil
}

func (s Store) withFileLock(operation func() error) (returnErr error) {
	path, err := s.path()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create pull request cache directory: %w", err)
	}
	lock, err := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return fmt.Errorf("open pull request cache lock: %w", err)
	}
	if err := lock.Chmod(0o600); err != nil {
		_ = lock.Close()
		return err
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		_ = lock.Close()
		return fmt.Errorf("lock pull request cache: %w", err)
	}
	defer func() {
		if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_UN); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("unlock pull request cache: %w", err)
		}
		if err := lock.Close(); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("close pull request cache lock: %w", err)
		}
	}()
	return operation()
}

func (s Store) path() (string, error) {
	if s.Path != "" {
		return filepath.Abs(s.Path)
	}
	return ResolveCachePath()
}

func (s Store) now() time.Time {
	if s.Now != nil {
		return s.Now().UTC()
	}
	return time.Now().UTC()
}

func validateCache(state *cacheState) error {
	if state.Version != cacheVersion {
		return fmt.Errorf("version must equal %d", cacheVersion)
	}
	if state.Projects == nil {
		state.Projects = map[string]string{}
	}
	if state.Repositories == nil {
		state.Repositories = map[string]cacheEntry{}
	}
	for key, entry := range state.Repositories {
		if strings.TrimSpace(key) == "" || strings.TrimSpace(entry.Repository) == "" {
			return errors.New("cached repository identity is required")
		}
		if entry.PullRequests == nil {
			entry.PullRequests = []model.ProjectPullRequest{}
			state.Repositories[key] = entry
		}
	}
	return nil
}

func sortCache(state *cacheState) {
	for key, entry := range state.Repositories {
		sort.Slice(entry.PullRequests, func(i, j int) bool {
			if !entry.PullRequests[i].UpdatedAt.Equal(entry.PullRequests[j].UpdatedAt) {
				return entry.PullRequests[i].UpdatedAt.After(entry.PullRequests[j].UpdatedAt)
			}
			return entry.PullRequests[i].Number < entry.PullRequests[j].Number
		})
		state.Repositories[key] = entry
	}
}
