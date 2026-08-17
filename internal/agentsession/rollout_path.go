package agentsession

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

func SafeCodexRolloutPath(path, home string) (string, error) {
	if path == "" || home == "" {
		return "", errors.New("codex rollout path is unavailable")
	}
	root := filepath.Join(home, ".codex", "sessions")
	rootAbs, err := filepath.EvalSymlinks(root)
	if err != nil {
		return "", err
	}
	pathAbs, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", err
	}
	relative, err := filepath.Rel(rootAbs, pathAbs)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", errors.New("codex rollout path escapes the sessions root")
	}
	info, err := os.Lstat(pathAbs)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() {
		return "", errors.New("codex rollout is not a regular file")
	}
	return pathAbs, nil
}
