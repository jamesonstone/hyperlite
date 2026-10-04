package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"syscall"

	"go.yaml.in/yaml/v3"
)

type Writer interface {
	Write(path string, cfg Config) error
}

type AtomicWriter struct{}

var mutationMutex sync.Mutex

// Mutate serializes a configuration read-modify-write across goroutines and
// processes. The callback reports whether its changes should be persisted.
func Mutate(path string, mutate func(*Config) (bool, error)) error {
	resolved, err := ResolvePath(path)
	if err != nil {
		return err
	}
	mutationMutex.Lock()
	defer mutationMutex.Unlock()
	return withMutationLock(resolved, func() error {
		// Decide "no config yet" from the config file itself: a Load error can
		// also wrap ErrNotExist for a path inside the config, and treating that
		// as a missing file would overwrite the whole configuration.
		var cfg Config
		if _, statErr := os.Stat(resolved); errors.Is(statErr, os.ErrNotExist) {
			cfg = Config{Version: Version, Path: resolved}
		} else if cfg, err = Load(resolved); err != nil {
			return err
		}
		changed, err := mutate(&cfg)
		if err != nil {
			return err
		}
		if !changed {
			return nil
		}
		return (AtomicWriter{}).Write(resolved, cfg)
	})
}

func withMutationLock(path string, operation func() error) (returnErr error) {
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return fmt.Errorf("create config directory: %w", err)
	}
	lock, err := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return fmt.Errorf("open config lock: %w", err)
	}
	if err := lock.Chmod(0o600); err != nil {
		_ = lock.Close()
		return fmt.Errorf("secure config lock: %w", err)
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		_ = lock.Close()
		return fmt.Errorf("lock config: %w", err)
	}
	defer func() {
		if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_UN); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("unlock config: %w", err)
		}
		if err := lock.Close(); err != nil && returnErr == nil {
			returnErr = fmt.Errorf("close config lock: %w", err)
		}
	}()
	return operation()
}

func (AtomicWriter) Write(path string, cfg Config) error {
	contents, err := Marshal(cfg)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create config directory: %w", err)
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".hyperlite-config-*.yaml")
	if err != nil {
		return fmt.Errorf("create temporary config: %w", err)
	}
	temporary := file.Name()
	defer os.Remove(temporary)
	if err := file.Chmod(0o644); err != nil {
		file.Close()
		return fmt.Errorf("set config permissions: %w", err)
	}
	if _, err := file.Write(contents); err != nil {
		file.Close()
		return fmt.Errorf("write temporary config: %w", err)
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return fmt.Errorf("sync temporary config: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close temporary config: %w", err)
	}
	if err := os.Rename(temporary, path); err != nil {
		return fmt.Errorf("replace config %s: %w", path, err)
	}
	return nil
}

func Marshal(cfg Config) ([]byte, error) {
	ollamaModel, err := NormalizeOllamaModel(cfg.Settings.OllamaModel)
	if err != nil {
		return nil, err
	}
	cfg.Settings.OllamaModel = ollamaModel
	defaults := defaultSettings()
	if cfg.Settings.ScanInterval <= 0 {
		cfg.Settings.ScanInterval = defaults.ScanInterval
	}
	if cfg.Settings.TrackedRefreshInterval <= 0 {
		cfg.Settings.TrackedRefreshInterval = cfg.Settings.ScanInterval
	}
	if cfg.Settings.UntrackedProbeInterval <= 0 {
		cfg.Settings.UntrackedProbeInterval = defaults.UntrackedProbeInterval
	}
	if cfg.Settings.RemoteRefreshInterval <= 0 {
		cfg.Settings.RemoteRefreshInterval = defaults.RemoteRefreshInterval
	}
	if cfg.Settings.StaleAfter <= 0 {
		cfg.Settings.StaleAfter = defaults.StaleAfter
	}
	if cfg.Settings.MaxParallel == 0 {
		cfg.Settings.MaxParallel = defaults.MaxParallel
	}
	if cfg.Settings.GitHubAuthor == "" {
		cfg.Settings.GitHubAuthor = defaults.GitHubAuthor
	}
	if cfg.Settings.GitHubScope == "" {
		cfg.Settings.GitHubScope = defaults.GitHubScope
	}
	raw := rawConfig{
		Version: Version,
		Settings: rawSettings{
			ScanInterval:           cfg.Settings.ScanInterval.String(),
			TrackedRefreshInterval: cfg.Settings.TrackedRefreshInterval.String(),
			UntrackedProbeInterval: cfg.Settings.UntrackedProbeInterval.String(),
			RemoteRefreshInterval:  cfg.Settings.RemoteRefreshInterval.String(),
			StaleAfter:             cfg.Settings.StaleAfter.String(),
			MaxParallel:            cfg.Settings.MaxParallel,
			GitHubAuthor:           cfg.Settings.GitHubAuthor,
			GitHubScope:            string(cfg.Settings.GitHubScope),
			OllamaModel:            cfg.Settings.OllamaModel,
		},
	}
	for _, project := range cfg.Projects {
		raw.Projects = append(raw.Projects, rawSource(project))
	}
	for _, project := range cfg.MissingProjects {
		raw.Projects = append(raw.Projects, rawSource(project))
	}
	for _, retired := range cfg.RetiredProjects {
		raw.Retired = append(raw.Retired, rawRetired{
			Path: retired.Path, Reason: retired.Reason, RetiredAt: retired.RetiredAt.UTC(),
		})
	}
	for _, source := range cfg.Sources {
		raw.Sources = append(raw.Sources, rawSource{Path: source.Path})
	}
	for _, repository := range cfg.Repositories {
		raw.Repositories = append(raw.Repositories, rawRepository{
			Name: repository.Name, Path: repository.Path, GitHub: repository.GitHub,
			Base: repository.Base, Remote: repository.Remote,
		})
	}
	contents, err := yaml.Marshal(raw)
	if err != nil {
		return nil, fmt.Errorf("encode config: %w", err)
	}
	return contents, nil
}

// ReplaceProjectPaths replaces Hyperlite's project selection with exact
// repository roots while retaining any imported discovery inventory.
func ReplaceProjectPaths(current Config, paths []string) (Config, error) {
	selected := make(map[string]struct{}, len(paths))
	ignored := make(map[string]bool, len(current.Projects))
	for _, project := range current.Projects {
		ignored[project.Path] = project.Ignored
	}
	replacement := current
	replacement.Version = Version
	replacement.Projects = nil
	for _, path := range paths {
		project, err := normalizeSource(rawSource{Path: path})
		if err != nil {
			return Config{}, fmt.Errorf("project path %q: %w", path, err)
		}
		if _, exists := selected[project.Path]; exists {
			continue
		}
		selected[project.Path] = struct{}{}
		project.Ignored = ignored[project.Path]
		// Adding a project back ends its retirement.
		replacement.RetiredProjects = removeRetired(
			append([]RetiredProject(nil), replacement.RetiredProjects...), project.Path,
		)
		replacement.Projects = append(replacement.Projects, project)
	}
	Sort(&replacement)
	return replacement, nil
}

// SetProjectIgnored marks one configured project ignored or watched. It
// reports whether the configuration changed.
func SetProjectIgnored(current *Config, path string, ignored bool) (bool, error) {
	for index := range current.Projects {
		if current.Projects[index].Path != path {
			continue
		}
		if current.Projects[index].Ignored == ignored {
			return false, nil
		}
		current.Projects[index].Ignored = ignored
		return true, nil
	}
	return false, fmt.Errorf("project is not configured: %s", path)
}

func defaultSettings() Settings {
	settings, _ := normalizeSettings(rawSettings{})
	return settings
}

func Sort(cfg *Config) {
	sort.SliceStable(cfg.Projects, func(i, j int) bool { return cfg.Projects[i].Path < cfg.Projects[j].Path })
	sort.SliceStable(cfg.Sources, func(i, j int) bool { return cfg.Sources[i].Path < cfg.Sources[j].Path })
	sort.SliceStable(cfg.Repositories, func(i, j int) bool {
		if cfg.Repositories[i].Name != cfg.Repositories[j].Name {
			return cfg.Repositories[i].Name < cfg.Repositories[j].Name
		}
		return cfg.Repositories[i].Path < cfg.Repositories[j].Path
	})
}
