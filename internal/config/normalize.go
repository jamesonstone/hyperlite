package config

import (
	"errors"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"
	"unicode"
)

var githubName = regexp.MustCompile(`^[^/\s]+/[^/\s]+$`)

func normalize(raw rawConfig, path string) (Config, error) {
	if raw.Version != Version1 && raw.Version != Version {
		return Config{}, fmt.Errorf("config version must be %d or %d", Version1, Version)
	}
	if raw.Version == Version1 && len(raw.Sources) != 0 {
		return Config{}, errors.New("config version 1 does not support sources")
	}
	if raw.Version == Version1 && len(raw.Projects) != 0 {
		return Config{}, errors.New("config version 1 does not support projects")
	}
	if raw.Version == Version1 && raw.Settings.GitHubScope != "" {
		return Config{}, errors.New("config version 1 does not support settings.github_scope")
	}
	if raw.Version == Version1 && raw.Settings.OllamaModel != "" {
		return Config{}, errors.New("config version 1 does not support settings.ollama_model")
	}
	if raw.Version == Version1 && len(raw.Repositories) == 0 {
		return Config{}, errors.New("config must contain at least one source or repository")
	}
	settings, err := normalizeSettings(raw.Settings)
	if err != nil {
		return Config{}, err
	}
	config := Config{Version: raw.Version, Settings: settings, Path: path}
	seenProjects := make(map[string]struct{}, len(raw.Projects))
	for index, rawProject := range raw.Projects {
		project, err := normalizeSource(rawProject)
		if err != nil {
			return Config{}, fmt.Errorf("project %d: %w", index+1, err)
		}
		if _, exists := seenProjects[project.Path]; exists {
			return Config{}, fmt.Errorf("project path %q is duplicated", project.Path)
		}
		seenProjects[project.Path] = struct{}{}
		config.Projects = append(config.Projects, project)
	}
	seenSources := make(map[string]struct{}, len(raw.Sources))
	for index, rawSource := range raw.Sources {
		source, err := normalizeSource(rawSource)
		if err != nil {
			return Config{}, fmt.Errorf("source %d: %w", index+1, err)
		}
		if _, exists := seenSources[source.Path]; exists {
			return Config{}, fmt.Errorf("source path %q is duplicated", source.Path)
		}
		seenSources[source.Path] = struct{}{}
		config.Sources = append(config.Sources, source)
	}
	seen := make(map[string]struct{}, len(raw.Repositories))
	for index, rawRepo := range raw.Repositories {
		repo, err := normalizeRepository(rawRepo)
		if err != nil {
			return Config{}, fmt.Errorf("repository %d: %w", index+1, err)
		}
		if _, exists := seen[repo.Name]; exists {
			return Config{}, fmt.Errorf("repository name %q is duplicated", repo.Name)
		}
		seen[repo.Name] = struct{}{}
		config.Repositories = append(config.Repositories, repo)
	}
	return config, nil
}

func normalizeSettings(raw rawSettings) (Settings, error) {
	ollamaModel, err := NormalizeOllamaModel(raw.OllamaModel)
	if err != nil {
		return Settings{}, err
	}
	settings := Settings{
		MaxParallel: raw.MaxParallel, GitHubAuthor: raw.GitHubAuthor,
		GitHubScope: GitHubScope(strings.TrimSpace(raw.GitHubScope)),
		OllamaModel: ollamaModel,
	}
	if settings.MaxParallel == 0 {
		settings.MaxParallel = 4
	}
	if settings.MaxParallel < 1 || settings.MaxParallel > 32 {
		return Settings{}, errors.New("settings.max_parallel must be between 1 and 32")
	}
	if settings.GitHubAuthor == "" {
		settings.GitHubAuthor = "@me"
	}
	if settings.GitHubScope == "" {
		settings.GitHubScope = GitHubScopeMine
	}
	if settings.GitHubScope != GitHubScopeMine && settings.GitHubScope != GitHubScopeAll {
		return Settings{}, errors.New("settings.github_scope must be mine or all")
	}
	if settings.ScanInterval, err = durationOrDefault(raw.ScanInterval, time.Minute); err != nil {
		return Settings{}, fmt.Errorf("settings.scan_interval: %w", err)
	}
	if settings.TrackedRefreshInterval, err = durationOrDefault(raw.TrackedRefreshInterval, settings.ScanInterval); err != nil {
		return Settings{}, fmt.Errorf("settings.tracked_refresh_interval: %w", err)
	}
	if settings.UntrackedProbeInterval, err = durationOrDefault(raw.UntrackedProbeInterval, 10*time.Minute); err != nil {
		return Settings{}, fmt.Errorf("settings.untracked_probe_interval: %w", err)
	}
	if settings.RemoteRefreshInterval, err = durationOrDefault(raw.RemoteRefreshInterval, 45*time.Minute); err != nil {
		return Settings{}, fmt.Errorf("settings.remote_refresh_interval: %w", err)
	}
	if settings.StaleAfter, err = durationOrDefault(raw.StaleAfter, 24*time.Hour); err != nil {
		return Settings{}, fmt.Errorf("settings.stale_after: %w", err)
	}
	return settings, nil
}

func NormalizeOllamaModel(value string) (string, error) {
	value = strings.TrimSpace(value)
	if len(value) > 200 {
		return "", errors.New("settings.ollama_model must be at most 200 characters")
	}
	if strings.IndexFunc(value, unicode.IsControl) >= 0 {
		return "", errors.New("settings.ollama_model must not contain control characters")
	}
	return value, nil
}

func normalizeSource(raw rawSource) (Source, error) {
	if strings.TrimSpace(raw.Path) == "" {
		return Source{}, errors.New("path is required")
	}
	path, err := CanonicalizeSourcePath(raw.Path)
	if err != nil {
		return Source{}, err
	}
	info, err := os.Lstat(path)
	if err != nil {
		return Source{}, fmt.Errorf("inspect path %s: %w", path, err)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return Source{}, fmt.Errorf("source path must not be a symbolic link: %s", path)
	}
	if !info.IsDir() {
		return Source{}, fmt.Errorf("path is not a directory: %s", path)
	}
	return Source{Path: path}, nil
}

func normalizeRepository(raw rawRepository) (Repository, error) {
	repo := Repository{
		Name: strings.TrimSpace(raw.Name), GitHub: strings.TrimSpace(raw.GitHub),
		Base: strings.TrimSpace(raw.Base), Remote: strings.TrimSpace(raw.Remote),
	}
	if repo.Name == "" || raw.Path == "" || repo.GitHub == "" {
		return Repository{}, errors.New("name, path, and github are required")
	}
	if !githubName.MatchString(repo.GitHub) {
		return Repository{}, fmt.Errorf("github must use owner/repository form: %q", repo.GitHub)
	}
	if repo.Base == "" {
		repo.Base = "main"
	}
	if repo.Remote == "" {
		repo.Remote = "origin"
	}
	path, err := CanonicalizePath(raw.Path)
	if err != nil {
		return Repository{}, err
	}
	info, err := os.Stat(path)
	if err != nil {
		return Repository{}, fmt.Errorf("inspect path %s: %w", path, err)
	}
	if !info.IsDir() {
		return Repository{}, fmt.Errorf("path is not a directory: %s", path)
	}
	repo.Path = path
	return repo, nil
}

func durationOrDefault(value string, fallback time.Duration) (time.Duration, error) {
	if value == "" {
		return fallback, nil
	}
	duration, err := time.ParseDuration(value)
	if err != nil || duration <= 0 {
		return 0, fmt.Errorf("must be a positive Go duration: %q", value)
	}
	return duration, nil
}
