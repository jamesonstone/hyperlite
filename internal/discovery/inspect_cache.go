package discovery

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
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
	// sources are the global and system git configuration files git reads in
	// this process's environment, resolved once per discovery run.
	sources []string
	// disabled skips reuse and storage for this run.
	disabled bool
}

type cachedInspection struct {
	Sources    []string          `json:"sources"`
	Stamps     []fileStamp       `json:"stamps"`
	Repository config.Repository `json:"repository"`
	CommonDir  string            `json:"common_dir"`
}

// useSources records the configuration sources for this run. Entries saved
// under different sources (another environment, a new include) are not reused.
func (c *InspectCache) useSources(sources []string) {
	if c == nil {
		return
	}
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.sources = sources
	c.disabled = false
}

func (c *InspectCache) disable() {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.disabled = true
}

func (c *InspectCache) lookup(root string) (candidate, bool) {
	if c == nil {
		return candidate{}, false
	}
	c.mutex.Lock()
	c.loadLocked()
	entry, found := c.entries[root]
	sources, disabled := c.sources, c.disabled
	c.mutex.Unlock()
	if disabled || !found || !equalStrings(entry.Sources, sources) || !stampsCurrent(entry.Stamps) {
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
	c.mutex.Lock()
	sources, disabled := c.sources, c.disabled
	c.mutex.Unlock()
	if disabled {
		return
	}
	stamps := inspectionStamps(root, item.commonDir, item.repo.Remote, sources)
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.loadLocked()
	c.entries[root] = cachedInspection{
		Sources: sources, Stamps: stamps, Repository: item.repo, CommonDir: item.commonDir,
	}
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

func equalStrings(left, right []string) bool {
	return slices.Equal(left, right)
}
