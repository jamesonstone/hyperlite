package discovery

import (
	"bufio"
	"context"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type fileStamp struct {
	Path     string `json:"path"`
	Exists   bool   `json:"exists"`
	Size     int64  `json:"size"`
	ModNano  int64  `json:"mod_nano"`
	LinkNano int64  `json:"link_nano,omitempty"`
}

// maxIncludeDepth bounds include chains while following configuration files.
const maxIncludeDepth = 5

// prepareCache resolves this run's configuration sources before any lookup.
func (d Discoverer) prepareCache(ctx context.Context) {
	if d.Cache != nil {
		d.Cache.useSources(d.configSources(ctx))
	}
}

// configSources asks git, once per run, which global and system configuration
// files it reads in the current environment, including their includes and
// GIT_CONFIG_GLOBAL, XDG_CONFIG_HOME, or a non-default system path. Running
// outside any repository limits the answer to those scopes. A failure returns
// nil, which still yields exact behavior: entries saved with sources are not
// reused, and new entries stamp only repository files.
func (d Discoverer) configSources(ctx context.Context) []string {
	output, err := d.run(ctx, gitTimeout, os.TempDir(), "git", "config", "--list", "--show-origin", "--name-only")
	if err != nil {
		return nil
	}
	seen := map[string]struct{}{}
	var sources []string
	for _, line := range strings.Split(string(output), "\n") {
		origin, _, found := strings.Cut(line, "\t")
		path, isFile := strings.CutPrefix(origin, "file:")
		if !found || !isFile || path == "" {
			continue
		}
		if _, duplicate := seen[path]; !duplicate {
			seen[path] = struct{}{}
			sources = append(sources, path)
		}
	}
	sort.Strings(sources)
	return sources
}

// inspectionStamps lists every file whose change can alter the common
// directory, the GitHub remote, or the local base branch: the repository's
// git entry, configuration (with its includes), refs, and the global and
// system configuration sources.
func inspectionStamps(root, commonDir, remote string, sources []string) []fileStamp {
	paths := []string{
		filepath.Join(root, ".git"),
		filepath.Join(commonDir, "packed-refs"),
		filepath.Join(commonDir, "refs", "heads", "main"),
		filepath.Join(commonDir, "refs", "heads", "master"),
		filepath.Join(commonDir, "refs", "heads", "trunk"),
	}
	if remote != "" {
		paths = append(paths, filepath.Join(commonDir, "refs", "remotes", remote, "HEAD"))
	}
	configs := []string{filepath.Join(commonDir, "config"), filepath.Join(commonDir, "config.worktree")}
	if gitDir := linkedGitDir(root); gitDir != "" {
		configs = append(configs, filepath.Join(gitDir, "config.worktree"))
	}
	paths = append(paths, withIncludes(configs)...)
	paths = append(paths, sources...)
	stamps := make([]fileStamp, 0, len(paths))
	for _, path := range paths {
		stamps = append(stamps, stampFor(path))
	}
	return stamps
}

// withIncludes returns the configuration files plus every file they include,
// conditional or not, so any change that could affect a remote is stamped.
func withIncludes(files []string) []string {
	seen := map[string]struct{}{}
	var result []string
	var visit func(path string, depth int)
	visit = func(path string, depth int) {
		if _, done := seen[path]; done {
			return
		}
		seen[path] = struct{}{}
		result = append(result, path)
		if depth >= maxIncludeDepth {
			return
		}
		for _, included := range includePaths(path) {
			visit(included, depth+1)
		}
	}
	for _, file := range files {
		visit(file, 0)
	}
	return result
}

func includePaths(configPath string) []string {
	file, err := os.Open(configPath)
	if err != nil {
		return nil
	}
	defer file.Close()
	var paths []string
	inInclude := false
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "[") {
			section := strings.ToLower(strings.Trim(line, "[] "))
			inInclude = section == "include" || strings.HasPrefix(section, "includeif")
			continue
		}
		key, value, found := strings.Cut(line, "=")
		if !inInclude || !found || !strings.EqualFold(strings.TrimSpace(key), "path") {
			continue
		}
		paths = append(paths, resolveIncludePath(strings.Trim(strings.TrimSpace(value), `"`), configPath))
	}
	return paths
}

func resolveIncludePath(value, configPath string) string {
	if value == "~" || strings.HasPrefix(value, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(value, "~"))
		}
	}
	if filepath.IsAbs(value) {
		return value
	}
	return filepath.Join(filepath.Dir(configPath), value)
}

// linkedGitDir returns a linked worktree's private git directory, or "" for
// an ordinary repository whose .git is a directory.
func linkedGitDir(root string) string {
	contents, err := os.ReadFile(filepath.Join(root, ".git"))
	if err != nil {
		return ""
	}
	dir, found := strings.CutPrefix(strings.TrimSpace(string(contents)), "gitdir:")
	if !found {
		return ""
	}
	dir = strings.TrimSpace(dir)
	if !filepath.IsAbs(dir) {
		dir = filepath.Join(root, dir)
	}
	return filepath.Clean(dir)
}

// stampFor records the file a path resolves to, following symbolic links,
// plus the link itself so replacing either is detected.
func stampFor(path string) fileStamp {
	stamp := fileStamp{Path: path}
	if link, err := os.Lstat(path); err == nil && link.Mode()&os.ModeSymlink != 0 {
		stamp.LinkNano = link.ModTime().UnixNano()
	}
	info, err := os.Stat(path)
	if err != nil {
		return stamp
	}
	stamp.Exists = true
	stamp.Size = info.Size()
	stamp.ModNano = info.ModTime().UnixNano()
	return stamp
}

func stampsCurrent(stamps []fileStamp) bool {
	if len(stamps) == 0 {
		return false
	}
	for _, stamp := range stamps {
		if stampFor(stamp.Path) != stamp {
			return false
		}
	}
	return true
}
