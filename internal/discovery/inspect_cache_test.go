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
	if runner.calls.Load() != 0 || second.Repositories[0] != first.Repositories[0] {
		t.Fatalf("a persisted, unchanged inspection must spawn no git; calls=%d", runner.calls.Load())
	}

	if output, err := exec.Command("git", "-C", repo, "remote", "set-url", "origin", "https://github.com/owner/renamed.git").CombinedOutput(); err != nil {
		t.Fatalf("set-url: %v %s", err, output)
	}
	if _, err := os.Stat(filepath.Join(repo, ".git", "config")); err != nil {
		t.Fatal(err)
	}
	third := Discoverer{Runner: runner, Cache: &InspectCache{Path: cache.Path}}.Discover(context.Background(), sources)
	if runner.calls.Load() == 0 || third.Repositories[0].GitHub != "owner/renamed" {
		t.Fatalf("a changed git config must re-inspect; calls=%d got=%#v", runner.calls.Load(), third.Repositories)
	}
}
