package discovery

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"

	"github.com/jamesonstone/hyperlite/internal/config"
)

// InspectCache memoizes repository inspection between helper runs. Inspection
// spawns several git processes per repository; an entry is reused only while
// every file those commands read is unchanged, so results stay exact.
type InspectCache struct {
	Path    string
	mutex   sync.Mutex
	entries map[string]cachedInspection
	dirty   bool
	loaded  bool
}

type cachedInspection struct {
	Stamps     []fileStamp       `json:"stamps"`
	Repository config.Repository `json:"repository"`
	CommonDir  string            `json:"common_dir"`
}

type fileStamp struct {
	Path    string `json:"path"`
	Exists  bool   `json:"exists"`
	Size    int64  `json:"size"`
	ModNano int64  `json:"mod_nano"`
}

func (c *InspectCache) lookup(root string) (candidate, bool) {
	if c == nil {
		return candidate{}, false
	}
	c.mutex.Lock()
	c.loadLocked()
	entry, found := c.entries[root]
	c.mutex.Unlock()
	if !found || !stampsCurrent(entry.Stamps) {
		return candidate{}, false
	}
	repository := entry.Repository
	repository.CommonDir = entry.CommonDir
	return candidate{path: repository.Path, commonDir: entry.CommonDir, repo: repository}, true
}

func (c *InspectCache) store(root string, item candidate) {
	if c == nil {
		return
	}
	stamps := inspectionStamps(root, item.commonDir, item.repo.Remote)
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.loadLocked()
	c.entries[root] = cachedInspection{Stamps: stamps, Repository: item.repo, CommonDir: item.commonDir}
	c.dirty = true
}

// Save writes the cache when it changed. A failed write only costs a later
// re-inspection, so errors are ignored.
func (c *InspectCache) Save() {
	if c == nil {
		return
	}
	c.mutex.Lock()
	defer c.mutex.Unlock()
	if !c.dirty || c.Path == "" {
		return
	}
	encoded, err := json.Marshal(c.entries)
	if err != nil || os.MkdirAll(filepath.Dir(c.Path), 0o700) != nil {
		return
	}
	temporary := c.Path + ".tmp"
	if os.WriteFile(temporary, encoded, 0o600) == nil && os.Rename(temporary, c.Path) == nil {
		c.dirty = false
	}
}

func (c *InspectCache) loadLocked() {
	if c.loaded {
		return
	}
	c.loaded = true
	c.entries = map[string]cachedInspection{}
	if c.Path == "" {
		return
	}
	if contents, err := os.ReadFile(c.Path); err == nil {
		_ = json.Unmarshal(contents, &c.entries)
	}
	if c.entries == nil {
		c.entries = map[string]cachedInspection{}
	}
}

// inspectionStamps lists every file whose change can alter the common
// directory, the GitHub remote, or the local base branch.
func inspectionStamps(root, commonDir, remote string) []fileStamp {
	paths := []string{
		filepath.Join(root, ".git"),
		filepath.Join(commonDir, "config"),
		filepath.Join(commonDir, "packed-refs"),
		filepath.Join(commonDir, "refs", "heads", "main"),
		filepath.Join(commonDir, "refs", "heads", "master"),
		filepath.Join(commonDir, "refs", "heads", "trunk"),
	}
	paths = append(paths, "/etc/gitconfig")
	if remote != "" {
		paths = append(paths, filepath.Join(commonDir, "refs", "remotes", remote, "HEAD"))
	}
	if home, err := os.UserHomeDir(); err == nil {
		paths = append(paths, filepath.Join(home, ".gitconfig"), filepath.Join(home, ".config", "git", "config"))
	}
	if xdg := os.Getenv("XDG_CONFIG_HOME"); xdg != "" {
		paths = append(paths, filepath.Join(xdg, "git", "config"))
	}
	stamps := make([]fileStamp, 0, len(paths))
	for _, path := range paths {
		stamps = append(stamps, stampFor(path))
	}
	return stamps
}

func stampFor(path string) fileStamp {
	info, err := os.Lstat(path)
	if err != nil {
		return fileStamp{Path: path}
	}
	return fileStamp{Path: path, Exists: true, Size: info.Size(), ModNano: info.ModTime().UnixNano()}
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
