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
	projected := now.Add(time.Duration(float64(4875) / 2400 * float64(time.Hour)))
	path := filepath.Join(t.TempDir(), "state", "pull-requests.json")
	store := Store{Path: path, Now: func() time.Time { return now }}
	updated, err := store.Update(func(state *cacheState) {
		state.Projects["/repo/one"] = "owner/one"
		state.RateLimit = &model.GitHubRateLimit{
			Limit: 5000, Used: 125, Remaining: 4875,
			ResetAt: now.Add(time.Hour), Cost: 4, NodeCount: 12,
			ObservedAt: now,
			BurnRate: &model.GitHubRateLimitBurnRate{
				PointsPerHour: 2400, SampleSeconds: 300,
				ProjectedExhaustionAt: &projected,
			},
		}
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
		len(state.Repositories["owner/one"].PullRequests) != 1 ||
		state.RateLimit == nil || state.RateLimit.Used != 125 ||
		state.RateLimit.BurnRate == nil ||
		state.RateLimit.BurnRate.PointsPerHour != 2400 ||
		state.RateLimit.BurnRate.ProjectedExhaustionAt == nil ||
		!state.RateLimit.BurnRate.ProjectedExhaustionAt.Equal(projected) {
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

func TestStorePreservesCacheWithInvalidBurnRate(t *testing.T) {
	now := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "pull-requests.json")
	contents := []byte(`{
  "version": 1,
  "projects": {},
  "repositories": {},
  "rate_limit": {
    "limit": 5000,
    "used": 125,
    "remaining": 4875,
    "reset_at": "2026-08-02T13:00:00Z",
    "cost": 4,
    "node_count": 12,
    "observed_at": "2026-08-02T12:00:00Z",
    "burn_rate": {
      "points_per_hour": -1,
      "sample_seconds": 300,
      "projected_exhaustion_at": "2026-08-02T11:00:00Z"
    }
  },
  "updated_at": "2026-08-02T12:00:00Z"
}`)
	if err := os.WriteFile(path, contents, 0o600); err != nil {
		t.Fatal(err)
	}
	state, warning, err := (Store{
		Path: path, Now: func() time.Time { return now },
	}).Load()
	if err != nil || state.Version != cacheVersion || state.RateLimit != nil ||
		!strings.Contains(warning, "cached GitHub rate limit is incomplete or inconsistent") {
		t.Fatalf("state=%#v warning=%q err=%v", state, warning, err)
	}
	matches, err := filepath.Glob(path + ".corrupt-*")
	if err != nil || len(matches) != 1 {
		t.Fatalf("matches=%#v err=%v", matches, err)
	}
}

func TestStoreLoadsLegacyCacheWithoutRateLimit(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pull-requests.json")
	contents := []byte(`{
  "version": 1,
  "projects": {},
  "repositories": {},
  "updated_at": "2026-07-29T16:00:00Z"
}`)
	if err := os.WriteFile(path, contents, 0o600); err != nil {
		t.Fatal(err)
	}
	state, warning, err := (Store{Path: path}).Load()
	if err != nil || warning != "" || state.RateLimit != nil ||
		state.Version != cacheVersion {
		t.Fatalf("state=%#v warning=%q err=%v", state, warning, err)
	}
}

func TestStorePreservesCacheWithInconsistentRateLimit(t *testing.T) {
	now := time.Date(2026, 8, 2, 12, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "pull-requests.json")
	contents := []byte(`{
  "version": 1,
  "projects": {},
  "repositories": {},
  "rate_limit": {
    "limit": 5000,
    "used": 125,
    "remaining": 4800,
    "reset_at": "2026-08-02T13:00:00Z",
    "cost": 4,
    "node_count": 12,
    "observed_at": "2026-08-02T12:00:00Z"
  },
  "updated_at": "2026-08-02T12:00:00Z"
}`)
	if err := os.WriteFile(path, contents, 0o600); err != nil {
		t.Fatal(err)
	}
	state, warning, err := (Store{
		Path: path, Now: func() time.Time { return now },
	}).Load()
	if err != nil || state.Version != cacheVersion || state.RateLimit != nil ||
		!strings.Contains(warning, "cached GitHub rate limit is incomplete or inconsistent") {
		t.Fatalf("state=%#v warning=%q err=%v", state, warning, err)
	}
	matches, err := filepath.Glob(path + ".corrupt-*")
	if err != nil || len(matches) != 1 {
		t.Fatalf("matches=%#v err=%v", matches, err)
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
