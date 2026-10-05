package config

import (
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"go.yaml.in/yaml/v3"
)

const (
	Version1 = 1
	Version  = 2
)

type Settings struct {
	ScanInterval           time.Duration
	TrackedRefreshInterval time.Duration
	UntrackedProbeInterval time.Duration
	RemoteRefreshInterval  time.Duration
	StaleAfter             time.Duration
	MaxParallel            int
	GitHubAuthor           string
	GitHubScope            GitHubScope
	OllamaModel            string
}

type GitHubScope string

const (
	GitHubScopeMine GitHubScope = "mine"
	GitHubScopeAll  GitHubScope = "all"
)

type Source struct {
	Path string `yaml:"path" json:"path"`
	// Ignored projects stay listed but are skipped by every GitHub request.
	Ignored bool `yaml:"ignored,omitempty" json:"ignored,omitempty"`
}

type Repository struct {
	Name      string `yaml:"name" json:"name"`
	Path      string `yaml:"path" json:"path"`
	GitHub    string `yaml:"github" json:"github"`
	Base      string `yaml:"base" json:"base"`
	Remote    string `yaml:"remote" json:"remote"`
	CommonDir string `yaml:"-" json:"-"`
}

type Config struct {
	Version      int
	Settings     Settings
	Projects     []Source
	Sources      []Source
	Repositories []Repository
	// MissingProjects are configured projects whose directory no longer
	// exists. They load without failing and are written back unchanged until
	// RetireMissingProjects moves them to RetiredProjects.
	MissingProjects []Source
	// RetiredProjects are soft-deleted projects: kept for audit and restore,
	// never scanned.
	RetiredProjects []RetiredProject
	// ExcludedProjects are repositories under a source folder that the
	// operator removed; automatic discovery never re-adds them.
	ExcludedProjects []string
	Path             string
	// RefreshOnly is a per-invocation, never persisted limit on which project
	// paths a pull-request refresh may query.
	RefreshOnly []string
}

type RetiredProject struct {
	Path      string
	Reason    string
	RetiredAt time.Time
}

type rawConfig struct {
	Version      int             `yaml:"version"`
	Settings     rawSettings     `yaml:"settings"`
	Projects     []rawSource     `yaml:"projects"`
	Sources      []rawSource     `yaml:"sources"`
	Repositories []rawRepository `yaml:"repositories"`
	Retired      []rawRetired    `yaml:"retired_projects,omitempty"`
	Excluded     []string        `yaml:"excluded_projects,omitempty"`
}

type rawRetired struct {
	Path      string    `yaml:"path"`
	Reason    string    `yaml:"reason"`
	RetiredAt time.Time `yaml:"retired_at"`
}

type rawSettings struct {
	ScanInterval           string `yaml:"scan_interval"`
	TrackedRefreshInterval string `yaml:"tracked_refresh_interval"`
	UntrackedProbeInterval string `yaml:"untracked_probe_interval"`
	RemoteRefreshInterval  string `yaml:"remote_refresh_interval"`
	StaleAfter             string `yaml:"stale_after"`
	MaxParallel            int    `yaml:"max_parallel"`
	GitHubAuthor           string `yaml:"github_author"`
	GitHubScope            string `yaml:"github_scope"`
	OllamaModel            string `yaml:"ollama_model"`
}

type rawSource struct {
	Path    string `yaml:"path"`
	Ignored bool   `yaml:"ignored,omitempty"`
}

type rawRepository struct {
	Name   string `yaml:"name"`
	Path   string `yaml:"path"`
	GitHub string `yaml:"github"`
	Base   string `yaml:"base"`
	Remote string `yaml:"remote"`
}

func Load(path string) (Config, error) {
	resolved, err := ResolvePath(path)
	if err != nil {
		return Config{}, err
	}
	file, err := os.Open(resolved)
	if err != nil {
		return Config{}, fmt.Errorf("open config %s: %w", resolved, err)
	}
	defer file.Close()

	decoder := yaml.NewDecoder(file)
	decoder.KnownFields(true)
	var raw rawConfig
	if err := decoder.Decode(&raw); err != nil {
		return Config{}, fmt.Errorf("decode config %s: %w", resolved, err)
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return Config{}, fmt.Errorf("decode config %s: multiple YAML documents are not supported", resolved)
		}
		return Config{}, fmt.Errorf("decode config %s: %w", resolved, err)
	}
	return normalize(raw, resolved)
}
