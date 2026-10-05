package cli

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

// addNewSourceProjects watches Git repositories that appeared under the
// configured source folders since the project list was written. Repositories
// the operator removed (excluded), retired, or missing are never re-added.
func addNewSourceProjects(configPath string, cfg config.Config) ([]string, error) {
	if len(cfg.Sources) == 0 || len(cfg.Projects) == 0 {
		return nil, nil
	}
	var added []string
	err := config.Mutate(configPath, func(current *config.Config) (bool, error) {
		known := map[string]struct{}{}
		for _, project := range current.Projects {
			known[project.Path] = struct{}{}
		}
		for _, project := range current.MissingProjects {
			known[project.Path] = struct{}{}
		}
		for _, retired := range current.RetiredProjects {
			known[retired.Path] = struct{}{}
		}
		for _, excluded := range current.ExcludedProjects {
			known[excluded] = struct{}{}
		}
		added = nil
		for _, source := range current.Sources {
			roots, _ := discovery.RepositoryRoots(source.Path)
			for _, root := range roots {
				// Only primary checkouts: a linked worktree or submodule has a
				// .git file and belongs to a repository watched elsewhere.
				if info, err := os.Lstat(filepath.Join(root, ".git")); err != nil || !info.IsDir() {
					continue
				}
				if _, seen := known[root]; !seen {
					known[root] = struct{}{}
					added = append(added, root)
				}
			}
		}
		if len(added) == 0 {
			return false, nil
		}
		paths := make([]string, 0, len(current.Projects)+len(added))
		for _, project := range current.Projects {
			paths = append(paths, project.Path)
		}
		updated, err := config.ReplaceProjectPaths(*current, append(paths, added...))
		if err != nil {
			return false, err
		}
		*current = updated
		return true, nil
	})
	return added, err
}

func addedProjectWarnings(added []string) []model.ScanError {
	warnings := make([]model.ScanError, 0, len(added))
	for _, path := range added {
		warnings = append(warnings, model.ScanError{
			RepositoryPath: path, Stage: "project-added",
			Message: fmt.Sprintf("now watching %s, a new repository in a source folder; remove it with `hyperlite projects remove %s`", path, path),
		})
	}
	return warnings
}
