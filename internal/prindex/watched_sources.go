package prindex

import (
	"path/filepath"

	"github.com/jamesonstone/hyperlite/internal/config"
)

// watchedSources drops ignored projects, which no GitHub request may cover.
func watchedSources(sources []config.Source) []config.Source {
	watched := make([]config.Source, 0, len(sources))
	for _, source := range sources {
		if !source.Ignored {
			watched = append(watched, source)
		}
	}
	return watched
}

// fetchableSources is watchedSources narrowed to only, when only is set.
func fetchableSources(sources []config.Source, only []string) []config.Source {
	watched := watchedSources(sources)
	if len(only) == 0 {
		return watched
	}
	selected := make(map[string]struct{}, len(only))
	for _, path := range only {
		selected[filepath.Clean(path)] = struct{}{}
	}
	result := watched[:0]
	for _, source := range watched {
		if _, ok := selected[filepath.Clean(source.Path)]; ok {
			result = append(result, source)
		}
	}
	return result
}
