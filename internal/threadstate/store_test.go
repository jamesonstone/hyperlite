package threadstate

import (
	"bytes"
	"context"
	"os"
	"os/exec"
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

func TestStoreMutateSerializesAcrossProcesses(t *testing.T) {
	path := filepath.Join(t.TempDir(), "threads.json")
	if err := (Store{Path: path}).Write(Empty()); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	commands := make([]*exec.Cmd, 2)
	outputs := make([]*bytes.Buffer, 2)
	for index, id := range []string{"issue:owner/repo#1", "issue:owner/repo#2"} {
		command := exec.CommandContext(ctx, os.Args[0], "-test.run=TestStoreMutateProcessHelper")
		command.Env = append(os.Environ(),
			"HYPERLITE_MUTATE_HELPER=1",
			"HYPERLITE_MUTATE_PATH="+path,
			"HYPERLITE_MUTATE_ID="+id,
		)
		output := &bytes.Buffer{}
		command.Stdout = output
		command.Stderr = output
		if err := command.Start(); err != nil {
			t.Fatal(err)
		}
		commands[index] = command
		outputs[index] = output
	}
	for index, command := range commands {
		if err := command.Wait(); err != nil {
			t.Fatalf("helper failed: %v\n%s", err, outputs[index].Bytes())
		}
	}
	state, warning, err := (Store{Path: path}).Load()
	if err != nil || warning != "" || len(state.Threads) != 2 {
		t.Fatalf("state=%#v warning=%q err=%v", state, warning, err)
	}
}

func TestStoreMutateProcessHelper(t *testing.T) {
	if os.Getenv("HYPERLITE_MUTATE_HELPER") != "1" {
		t.Skip("subprocess helper")
	}
	path := os.Getenv("HYPERLITE_MUTATE_PATH")
	id := os.Getenv("HYPERLITE_MUTATE_ID")
	err := (Store{Path: path}).Mutate(func(state *State) error {
		time.Sleep(100 * time.Millisecond)
		state.Threads = append(state.Threads, ThreadRecord{
			ID: id, Aliases: []string{}, Moments: []model.AttentionMoment{},
		})
		return nil
	})
	if err != nil {
		t.Fatal(err)
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

func TestReconcileDemotesMissingThreadButRetainsPrivateState(t *testing.T) {
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
	SetInference(&state, thread.ID, "digest", model.InferenceThread{ThreadID: thread.ID}, now)

	values := ReconcileSelected(&state, nil, []string{"owner/repo"}, now.Add(time.Minute))
	if len(values) != 0 || len(state.Threads) != 1 ||
		!state.Threads[0].Missing || state.Threads[0].Snapshot.Active {
		t.Fatalf("missing thread projection = %#v state=%#v", values, state)
	}
	if len(state.Inferences) != 1 {
		t.Fatalf("missing thread lost cached inference: %#v", state.Inferences)
	}

	values = ReconcileSelected(&state, nil, []string{"owner/other"}, now.Add(2*time.Minute))
	if len(values) != 0 || len(state.Threads) != 0 || len(state.Inferences) != 0 {
		t.Fatalf("unselected repository leaked retained state: values=%#v state=%#v", values, state)
	}
}

func TestReconcileTerminalCorrectionDoesNotCreateAttentionOrRetainOldSnapshot(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := Empty()
	thread := model.Thread{
		ID: "spec:owner/repo:0001", Aliases: []string{"spec:owner/repo:0001"},
		Title: "Legacy feature", Goal: "Deliver legacy feature", Rationale: "Needed",
		Phase: model.ThreadReflecting, Active: true,
		Repositories: []string{"owner/repo"}, UpdatedAt: now,
	}
	ReconcileSelected(&state, []model.Thread{thread}, []string{"owner/repo"}, now)

	thread.Phase = model.ThreadComplete
	thread.Active = false
	values := ReconcileSelected(&state, []model.Thread{thread}, []string{"owner/repo"}, now.Add(time.Minute))
	if len(values) != 1 || len(values[0].Attention) != 0 {
		t.Fatalf("terminal correction created attention: %#v", values)
	}

	thread.UpdatedAt = time.Time{}
	values = ReconcileSelected(&state, []model.Thread{thread}, []string{"owner/repo"}, now.Add(2*time.Minute))
	if len(values) != 0 || len(state.Threads) != 0 {
		t.Fatalf("old terminal correction was retained: values=%#v state=%#v", values, state)
	}
}

func TestReconcileDormantProjectionRetiresUnreadAttention(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := Empty()
	thread := model.Thread{
		ID: "issue:owner/repo#1", Aliases: []string{"issue:owner/repo#1"},
		Title: "Delivered", Goal: "Deliver feature", Rationale: "Needed",
		Phase: model.ThreadReflecting, Active: true,
		Repositories: []string{"owner/repo"}, UpdatedAt: now,
		Implications: []model.ThreadImplication{{
			Summary: "Choose the durable boundary", Category: "review_decision",
			Basis: model.BasisExtracted, EvidenceIDs: []string{"review:1"},
		}},
		Evidence: []model.EvidenceRef{{ID: "review:1", Freshness: "current"}},
	}
	values := ReconcileSelected(&state, []model.Thread{thread}, []string{"owner/repo"}, now)
	if len(values) != 1 || len(values[0].Attention) != 1 {
		t.Fatalf("active values = %#v", values)
	}

	thread.Active = false
	values = ReconcileSelected(
		&state, []model.Thread{thread}, []string{"owner/repo"}, now.Add(time.Minute),
	)
	if len(values) != 0 || len(state.Threads) != 0 {
		t.Fatalf("dormant attention remained visible: values=%#v state=%#v", values, state)
	}
}
