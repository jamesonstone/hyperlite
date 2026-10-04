package config

import (
	"fmt"
	"time"
)

// RetiredMissingDirectory is the reason recorded when a project's local
// directory disappeared.
const RetiredMissingDirectory = "local directory no longer exists"

// RetireMissingProjects soft-deletes every configured project whose
// directory is gone and returns what it retired. A project is restorable with
// RestoreRetiredProject once its directory exists again.
func RetireMissingProjects(cfg *Config, now time.Time) []RetiredProject {
	var retired []RetiredProject
	for _, missing := range cfg.MissingProjects {
		entry := RetiredProject{Path: missing.Path, Reason: RetiredMissingDirectory, RetiredAt: now.UTC()}
		cfg.RetiredProjects = removeRetired(cfg.RetiredProjects, missing.Path)
		cfg.RetiredProjects = append(cfg.RetiredProjects, entry)
		retired = append(retired, entry)
	}
	cfg.MissingProjects = nil
	return retired
}

// RestoreRetiredProject moves a retired project back into the scan list. The
// directory must be a canonical source path that exists again.
func RestoreRetiredProject(cfg *Config, path string) error {
	found := false
	for _, retired := range cfg.RetiredProjects {
		if retired.Path == path {
			found = true
		}
	}
	if !found {
		return fmt.Errorf("project is not retired: %s", path)
	}
	project, err := normalizeSource(rawSource{Path: path})
	if err != nil {
		return fmt.Errorf("restore %s: %w", path, err)
	}
	cfg.RetiredProjects = removeRetired(cfg.RetiredProjects, path)
	for _, existing := range cfg.Projects {
		if existing.Path == project.Path {
			return nil
		}
	}
	cfg.Projects = append(cfg.Projects, project)
	Sort(cfg)
	return nil
}

func removeRetired(retired []RetiredProject, path string) []RetiredProject {
	kept := retired[:0]
	for _, entry := range retired {
		if entry.Path != path {
			kept = append(kept, entry)
		}
	}
	return kept
}
