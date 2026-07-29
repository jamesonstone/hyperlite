package prindex

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestStoreRoundTripUsesPrivateAtomicCache(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "state", "pull-requests.json")
	store := Store{Path: path, Now: func() time.Time { return now }}
	updated, err := store.Update(func(state *cacheState) {
		state.Projects["/repo/one"] = "owner/one"
		state.Repositories["owner/one"] = cacheEntry{
			Repository: "owner/one", ObservedAt: now,
			PullRequests: []model.ProjectPullRequest{{
				ID: "owner/one#1", Number: 1, Title: "One",
			}},
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	state, warning, err := store.Load()
	if err != nil || warning != "" ||
		state.Projects["/repo/one"] != "owner/one" ||
		len(state.Repositories["owner/one"].PullRequests) != 1 {
		t.Fatalf("state=%#v warning=%q err=%v", state, warning, err)
	}
	if !updated.UpdatedAt.Equal(state.UpdatedAt) || !updated.UpdatedAt.Equal(now) {
		t.Fatalf("updated=%s persisted=%s want=%s", updated.UpdatedAt, state.UpdatedAt, now)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %o", info.Mode().Perm())
	}
}

func TestStorePreservesCorruptCache(t *testing.T) {
	now := time.Date(2026, 7, 29, 16, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "pull-requests.json")
	if err := os.WriteFile(path, []byte("{broken"), 0o600); err != nil {
		t.Fatal(err)
	}
	state, warning, err := (Store{
		Path: path, Now: func() time.Time { return now },
	}).Load()
	if err != nil || state.Version != cacheVersion ||
		!strings.Contains(warning, "preserved corrupt pull request cache") {
		t.Fatalf("state=%#v warning=%q err=%v", state, warning, err)
	}
	matches, err := filepath.Glob(path + ".corrupt-*")
	if err != nil || len(matches) != 1 {
		t.Fatalf("matches=%#v err=%v", matches, err)
	}
}
