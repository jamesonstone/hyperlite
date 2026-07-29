package workscan

import (
	"path/filepath"
	"sort"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/gitscan"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func buildProjectIndex(
	cfg config.Config,
	results []repositoryResult,
	threads []model.Thread,
) []model.ProjectIndexEntry {
	activePaths := activeWorktreePaths(threads)
	byPath := make(map[string]model.ProjectIndexEntry, len(results))
	for _, result := range results {
		entry := filteredProjectEntry(
			result.project,
			activePaths[result.project.Repository],
		)
		byPath[filepath.Clean(entry.Path)] = entry
	}

	if len(cfg.Projects) == 0 {
		entries := make([]model.ProjectIndexEntry, 0, len(results))
		for _, result := range results {
			entries = append(entries, filteredProjectEntry(
				result.project,
				activePaths[result.project.Repository],
			))
		}
		return entries
	}

	entries := make([]model.ProjectIndexEntry, 0, len(cfg.Projects))
	for _, configured := range cfg.Projects {
		path := filepath.Clean(configured.Path)
		if entry, found := byPath[path]; found {
			entries = append(entries, entry)
			continue
		}
		entries = append(entries, fallbackProjectEntry(path))
	}
	return entries
}

func activeWorktreePaths(threads []model.Thread) map[string]map[string]struct{} {
	paths := make(map[string]map[string]struct{})
	for _, thread := range threads {
		if !thread.Active {
			continue
		}
		for _, artifact := range thread.Artifacts {
			if artifact.Kind != model.ArtifactWorktree ||
				strings.TrimSpace(artifact.Path) == "" {
				continue
			}
			for _, repository := range thread.Repositories {
				if paths[repository] == nil {
					paths[repository] = make(map[string]struct{})
				}
				paths[repository][filepath.Clean(artifact.Path)] = struct{}{}
			}
		}
	}
	return paths
}

func filteredProjectEntry(
	entry model.ProjectIndexEntry,
	activePaths map[string]struct{},
) model.ProjectIndexEntry {
	lanes := make([]model.ProjectLane, 0, len(entry.Lanes))
	for _, lane := range entry.Lanes {
		if lane.Primary {
			lanes = append(lanes, lane)
			continue
		}
		if _, active := activePaths[filepath.Clean(lane.Path)]; active {
			lanes = append(lanes, lane)
		}
	}
	entry.Lanes = lanes
	return entry
}

func projectIndexEntry(
	repository config.Repository,
	locals []gitscan.LocalLane,
) model.ProjectIndexEntry {
	path := filepath.Clean(repository.Path)
	entry := model.ProjectIndexEntry{
		ID: path, Name: repository.Name, Path: path,
		Repository: repository.GitHub,
		Lanes: []model.ProjectLane{{
			ID: path, Branch: repository.Base, Path: path, Primary: true,
		}},
	}
	if entry.Name == "" {
		entry.Name = filepath.Base(path)
	}

	byPath := map[string]model.ProjectLane{path: entry.Lanes[0]}
	for _, local := range locals {
		lanePath := strings.TrimSpace(local.Worktree.Path)
		if lanePath == "" || local.Worktree.Prunable {
			continue
		}
		lanePath = filepath.Clean(lanePath)
		byPath[lanePath] = model.ProjectLane{
			ID: lanePath, Branch: local.Branch, Path: lanePath,
			Primary: lanePath == path, Detached: local.Worktree.Detached,
		}
	}
	entry.Lanes = entry.Lanes[:0]
	for _, lane := range byPath {
		entry.Lanes = append(entry.Lanes, lane)
	}
	sort.Slice(entry.Lanes, func(i, j int) bool {
		if entry.Lanes[i].Primary != entry.Lanes[j].Primary {
			return entry.Lanes[i].Primary
		}
		if entry.Lanes[i].Path != entry.Lanes[j].Path {
			return entry.Lanes[i].Path < entry.Lanes[j].Path
		}
		return entry.Lanes[i].Branch < entry.Lanes[j].Branch
	})
	return entry
}

func fallbackProjectEntry(path string) model.ProjectIndexEntry {
	return model.ProjectIndexEntry{
		ID: path, Name: filepath.Base(path), Path: path,
		Lanes: []model.ProjectLane{{ID: path, Path: path, Primary: true}},
	}
}
