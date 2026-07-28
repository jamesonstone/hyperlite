package threadstate

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestStoreWrites0600AndPreservesCorruptState(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "state", "threads.json")
	store := Store{Path: path, Now: func() time.Time { return now }}
	state := Empty()
	state.Threads = []ThreadRecord{{ID: "issue:owner/repo#1", Aliases: []string{}, Moments: []model.AttentionMoment{}}}
	if err := store.Write(state); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %o, want 600", info.Mode().Perm())
	}
	loaded, warning, err := store.Load()
	if err != nil || warning != "" || len(loaded.Threads) != 1 {
		t.Fatalf("load = %#v, warning = %q, err = %v", loaded, warning, err)
	}

	if err := os.WriteFile(path, []byte("{broken"), 0o600); err != nil {
		t.Fatal(err)
	}
	loaded, warning, err = store.Load()
	if err != nil {
		t.Fatal(err)
	}
	if len(loaded.Threads) != 0 || !strings.Contains(warning, ".corrupt-20260728T120000Z") {
		t.Fatalf("degraded load = %#v, warning = %q", loaded, warning)
	}
	if _, err := os.Stat(path + ".corrupt-20260728T120000Z"); err != nil {
		t.Fatalf("corrupt backup missing: %v", err)
	}
}

func TestReconcileMigratesSeenStateAndNoteToStrongerAnchor(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := Empty()
	branchID := "branch:owner/repo@GH-7"
	initial := model.Thread{
		ID: branchID, Aliases: []string{branchID}, Title: "Feature", Goal: "Deliver feature",
		Rationale: "Needed now", Phase: model.ThreadReviewing, Active: true,
		Implications: []model.ThreadImplication{{
			Summary: "Architecture ownership must be decided", Category: "review_decision",
			Basis: model.BasisExtracted, EvidenceIDs: []string{"review:1"},
		}},
		Evidence: []model.EvidenceRef{{ID: "review:1", Freshness: "current"}},
	}
	values := Reconcile(&state, []model.Thread{initial}, now)
	if len(values[0].Attention) != 1 {
		t.Fatalf("bootstrap moments = %#v", values[0].Attention)
	}
	revision := values[0].LatestMaterialRevision
	if err := MarkSeen(&state, branchID, revision); err != nil {
		t.Fatal(err)
	}
	if err := SetNote(&state, branchID, "deploy after the migration"); err != nil {
		t.Fatal(err)
	}

	issueID := "issue:owner/repo#7"
	promoted := initial
	promoted.ID = issueID
	promoted.Aliases = []string{issueID, branchID}
	values = Reconcile(&state, []model.Thread{promoted}, now.Add(time.Minute))
	if len(state.Threads) != 1 || state.Threads[0].ID != issueID {
		t.Fatalf("promoted records = %#v", state.Threads)
	}
	if values[0].Note != "deploy after the migration" || !values[0].Attention[0].Seen {
		t.Fatalf("migrated thread = %#v", values[0])
	}
}

func TestReconcileIgnoresRoutineArtifactChurn(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := Empty()
	thread := model.Thread{
		ID: "branch:owner/repo@GH-1", Aliases: []string{"branch:owner/repo@GH-1"},
		Title: "Feature", Goal: "Deliver feature", Rationale: "Needed",
		Phase: model.ThreadImplementing, Active: true,
		Artifacts: []model.ThreadArtifact{{ID: "git:1", Kind: model.ArtifactWorktree, State: "ahead"}},
	}
	values := Reconcile(&state, []model.Thread{thread}, now)
	if len(values[0].Attention) != 0 {
		t.Fatalf("initial ordinary progress created attention: %#v", values[0].Attention)
	}
	thread.Artifacts[0].State = "dirty"
	values = Reconcile(&state, []model.Thread{thread}, now.Add(time.Minute))
	if len(values[0].Attention) != 0 {
		t.Fatalf("ordinary churn created attention: %#v", values[0].Attention)
	}
}

func TestReconcileRetainsMissingActiveThreadOnlyWhileRepositorySelected(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := Empty()
	thread := model.Thread{
		ID: "branch:owner/repo@GH-1", Aliases: []string{"branch:owner/repo@GH-1"},
		Title: "Feature", Goal: "Deliver feature", Rationale: "Needed",
		Phase: model.ThreadImplementing, Active: true,
		Repositories: []string{"owner/repo"},
		Artifacts: []model.ThreadArtifact{{
			ID: "git:owner/repo@GH-1", Kind: model.ArtifactWorktree,
			State: "ahead", Freshness: "current",
		}},
		Evidence: []model.EvidenceRef{{
			ID: "git:owner/repo@GH-1", Freshness: "current",
		}},
	}
	ReconcileSelected(&state, []model.Thread{thread}, []string{"owner/repo"}, now)

	values := ReconcileSelected(&state, nil, []string{"owner/repo"}, now.Add(time.Minute))
	if len(values) != 1 || !values[0].Active ||
		values[0].Artifacts[0].Freshness != "stale" ||
		len(values[0].Attention) != 1 ||
		values[0].Attention[0].Kind != model.AttentionUncertain {
		t.Fatalf("retained thread = %#v", values)
	}

	values = ReconcileSelected(&state, nil, []string{"owner/other"}, now.Add(2*time.Minute))
	if len(values) != 0 {
		t.Fatalf("unselected repository leaked retained threads: %#v", values)
	}
}
