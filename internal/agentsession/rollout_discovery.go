package agentsession

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type rolloutCandidate struct {
	path string
	seed Event
}

func codexDateDirectory(home string, now time.Time) string {
	local := now.In(time.Local)
	return filepath.Join(home, ".codex", "sessions",
		local.Format("2006"), local.Format("01"), local.Format("02"))
}

func nextLocalDay(now time.Time) time.Time {
	local := now.In(time.Local)
	return time.Date(local.Year(), local.Month(), local.Day()+1, 0, 0, 0, 0, local.Location())
}

func watchableCodexDirectory(home string, now time.Time) string {
	target := codexDateDirectory(home, now)
	root := filepath.Join(home, ".codex", "sessions")
	for current := target; strings.HasPrefix(current, root); current = filepath.Dir(current) {
		if info, err := os.Stat(current); err == nil && info.IsDir() {
			return current
		}
		if current == root {
			break
		}
	}
	return ""
}

func discoverCodexRollouts(home string, now time.Time) []rolloutCandidate {
	directory := codexDateDirectory(home, now)
	entries, err := os.ReadDir(directory)
	if err != nil {
		return nil
	}
	type found struct {
		path    string
		updated time.Time
	}
	values := make([]found, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".jsonl" {
			continue
		}
		path, err := SafeCodexRolloutPath(filepath.Join(directory, entry.Name()), home)
		if err != nil {
			continue
		}
		info, err := entry.Info()
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		values = append(values, found{path: path, updated: info.ModTime()})
	}
	sort.Slice(values, func(i, j int) bool {
		if !values[i].updated.Equal(values[j].updated) {
			return values[i].updated.After(values[j].updated)
		}
		return values[i].path < values[j].path
	})
	result := make([]rolloutCandidate, 0, min(len(values), maxCodexRolloutWatches))
	for _, value := range values {
		result = append(result, rolloutCandidate{path: value.path, seed: Event{
			Schema: EventSchema, Provider: "codex", Profile: "codex", Source: SourceRollout,
			Event: "rollout/discovered", Phase: PhaseIdle, OccurredAt: value.updated,
			RolloutPath: value.path, Routing: Routing{BundleID: "com.openai.codex"},
		}})
		if len(result) == maxCodexRolloutWatches {
			break
		}
	}
	return result
}
