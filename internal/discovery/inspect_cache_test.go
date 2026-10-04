package discovery

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"sync/atomic"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
)

type countingRunner struct {
	calls atomic.Int32
}

func (r *countingRunner) Run(ctx context.Context, dir, name string, args ...string) ([]byte, error) {
	r.calls.Add(1)
	return command.ExecRunner{}.Run(ctx, dir, name, args...)
}

func gitRepository(t *testing.T, remote string) string {
	t.Helper()
	root, _ := filepath.EvalSymlinks(t.TempDir())
	repo := filepath.Join(root, "repo")
	for _, args := range [][]string{
		{"init", "-q", "-b", "main", repo},
		{"-C", repo, "remote", "add", "origin", remote},
	} {
		if output, err := exec.Command("git", args...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v %s", args, err, output)
		}
	}
	return repo
}

func TestInspectCacheReusesUntilGitConfigChanges(t *testing.T) {
	repo := gitRepository(t, "git@github.com:owner/first.git")
	cache := &InspectCache{Path: filepath.Join(t.TempDir(), "discovery.json")}
	runner := &countingRunner{}
	discoverer := Discoverer{Runner: runner, Cache: cache}
	sources := []config.Source{{Path: repo}}

	first := discoverer.Discover(context.Background(), sources)
	if len(first.Repositories) != 1 || first.Repositories[0].GitHub != "owner/first" || runner.calls.Load() == 0 {
		t.Fatalf("first = %#v calls=%d", first, runner.calls.Load())
	}
	runner.calls.Store(0)
	reloaded := Discoverer{Runner: runner, Cache: &InspectCache{Path: cache.Path}}
	second := reloaded.Discover(context.Background(), sources)
	if runner.calls.Load() != 1 || second.Repositories[0] != first.Repositories[0] {
		t.Fatalf("a persisted, unchanged inspection spawns only the config-sources probe; calls=%d", runner.calls.Load())
	}

	if output, err := exec.Command("git", "-C", repo, "remote", "set-url", "origin", "https://github.com/owner/renamed.git").CombinedOutput(); err != nil {
		t.Fatalf("set-url: %v %s", err, output)
	}
	if _, err := os.Stat(filepath.Join(repo, ".git", "config")); err != nil {
		t.Fatal(err)
	}
	runner.calls.Store(0)
	third := Discoverer{Runner: runner, Cache: &InspectCache{Path: cache.Path}}.Discover(context.Background(), sources)
	if runner.calls.Load() <= 1 || third.Repositories[0].GitHub != "owner/renamed" {
		t.Fatalf("a changed git config must re-inspect; calls=%d got=%#v", runner.calls.Load(), third.Repositories)
	}
}

func TestInspectCacheInvalidatesOnIncludeSymlinkAndSourceChanges(t *testing.T) {
	repo := gitRepository(t, "git@github.com:owner/first.git")
	dir := t.TempDir()
	included := filepath.Join(dir, "included.conf")
	target := filepath.Join(dir, "target.conf")
	link := filepath.Join(dir, "link.conf")
	if err := os.WriteFile(included, []byte("[core]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte("[core]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	configFile, err := os.OpenFile(filepath.Join(repo, ".git", "config"), os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = configFile.WriteString("[includeIf \"gitdir:" + repo + "/\"]\n\tpath = " + included + "\n")
	_ = configFile.Close()

	stamps := inspectionStamps(repo, filepath.Join(repo, ".git"), "origin", []string{link})
	if !stampsCurrent(stamps) {
		t.Fatal("fresh stamps must be current")
	}
	if err := os.WriteFile(included, []byte("[core]\n\tbare = false\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if stampsCurrent(stamps) {
		t.Fatal("an edited included config must invalidate the entry")
	}
	stamps = inspectionStamps(repo, filepath.Join(repo, ".git"), "origin", []string{link})
	if err := os.WriteFile(target, []byte("[core]\n\tbare = false\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if stampsCurrent(stamps) {
		t.Fatal("editing a symlinked config's target must invalidate the entry")
	}

	cache := &InspectCache{}
	cache.useSources([]string{"/one"})
	cache.store(repo, candidate{path: repo, commonDir: filepath.Join(repo, ".git"), repo: config.Repository{Path: repo, GitHub: "owner/first", Remote: "origin"}})
	if _, ok := cache.lookup(repo); !ok {
		t.Fatal("unchanged sources reuse the entry")
	}
	cache.useSources([]string{"/two"})
	if _, ok := cache.lookup(repo); ok {
		t.Fatal("a different set of configuration sources must not reuse the entry")
	}
}

func TestParseConfigValueFollowsGitRules(t *testing.T) {
	for raw, want := range map[string]string{
		` included.conf # note`:       "included.conf",
		`included.conf;comment`:       "included.conf",
		`"has # hash.conf" ; comment`: "has # hash.conf",
		`dir\ name/x.conf`:            "dir name/x.conf",
		`~/a b.conf`:                  "~/a b.conf",
	} {
		if got := parseConfigValue(raw); got != want {
			t.Errorf("parseConfigValue(%q) = %q, want %q", raw, got, want)
		}
	}
}

func TestInspectCacheFollowsGlobalIncludesAndSkipsCommandScope(t *testing.T) {
	repo := gitRepository(t, "git@github.com:owner/first.git")
	dir := t.TempDir()
	global := filepath.Join(dir, "global.conf")
	conditional := filepath.Join(dir, "conditional.conf")
	_ = os.WriteFile(conditional, []byte("[core]\n"), 0o600)
	_ = os.WriteFile(global, []byte("[includeIf \"gitdir:"+repo+"/\"]\n\tpath = "+conditional+" # repo only\n"), 0o600)
	stamps := inspectionStamps(repo, filepath.Join(repo, ".git"), "origin", []string{global})
	if err := os.WriteFile(conditional, []byte("[core]\n\tbare = false\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if stampsCurrent(stamps) {
		t.Fatal("editing a global gitdir-conditional include must invalidate the entry")
	}

	t.Setenv("GIT_CONFIG_COUNT", "1")
	cache := &InspectCache{Path: filepath.Join(t.TempDir(), "d.json")}
	runner := &countingRunner{}
	discoverer := Discoverer{Runner: runner, Cache: cache}
	sources := []config.Source{{Path: repo}}
	discoverer.Discover(context.Background(), sources)
	runner.calls.Store(0)
	discoverer.Discover(context.Background(), sources)
	if runner.calls.Load() == 0 {
		t.Fatal("command-scope configuration must bypass reuse")
	}
}
