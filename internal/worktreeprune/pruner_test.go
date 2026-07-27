package worktreeprune

import (
	"context"
	"errors"
	"reflect"
	"testing"
)

func TestPruneVerifiesTargetBeforeAndAfterMutation(t *testing.T) {
	runner := &scriptedRunner{responses: []response{
		{output: []byte("worktree /repo\x00HEAD abc\x00\x00worktree /stale\x00HEAD def\x00prunable gitdir file points to non-existent location\x00\x00")},
		{},
		{},
		{output: []byte("worktree /repo\x00HEAD abc\x00\x00")},
	}}
	if err := (Pruner{Runner: runner}).Prune(t.Context(), "/repo", "/stale"); err != nil {
		t.Fatal(err)
	}
	want := []call{
		{dir: "/repo", args: []string{"worktree", "list", "--porcelain", "-z"}},
		{dir: "/repo", args: []string{"worktree", "prune", "--dry-run", "--expire", "now", "--verbose"}},
		{dir: "/repo", args: []string{"worktree", "prune", "--expire", "now", "--verbose"}},
		{dir: "/repo", args: []string{"worktree", "list", "--porcelain", "-z"}},
	}
	if !reflect.DeepEqual(runner.calls, want) {
		t.Fatalf("calls = %#v, want %#v", runner.calls, want)
	}
}

func TestPruneRefusesUnverifiedTarget(t *testing.T) {
	runner := &scriptedRunner{responses: []response{{output: []byte(
		"worktree /repo\x00HEAD abc\x00\x00worktree /active\x00HEAD def\x00\x00",
	)}}}
	err := (Pruner{Runner: runner}).Prune(t.Context(), "/repo", "/active")
	if err == nil || err.Error() != "worktree is no longer prunable: /active" {
		t.Fatalf("err = %v", err)
	}
	if len(runner.calls) != 1 {
		t.Fatalf("calls = %#v", runner.calls)
	}
}

func TestPruneReportsTargetThatRemains(t *testing.T) {
	const records = "worktree /repo\x00HEAD abc\x00\x00worktree /stale\x00HEAD def\x00prunable stale\x00\x00"
	runner := &scriptedRunner{responses: []response{
		{output: []byte(records)}, {}, {}, {output: []byte(records)},
	}}
	err := (Pruner{Runner: runner}).Prune(t.Context(), "/repo", "/stale")
	if err == nil || err.Error() != "worktree metadata remains after prune: /stale" {
		t.Fatalf("err = %v", err)
	}
}

func TestPrunePropagatesGitFailure(t *testing.T) {
	runner := &scriptedRunner{responses: []response{
		{output: []byte("worktree /stale\x00HEAD def\x00prunable stale\x00\x00")},
		{},
		{err: errors.New("permission denied")},
	}}
	err := (Pruner{Runner: runner}).Prune(t.Context(), "/repo", "/stale")
	if err == nil || err.Error() != "prune stale worktrees: permission denied" {
		t.Fatalf("err = %v", err)
	}
}

type call struct {
	dir  string
	args []string
}

type response struct {
	output []byte
	err    error
}

type scriptedRunner struct {
	responses []response
	calls     []call
}

func (r *scriptedRunner) Run(_ context.Context, dir, name string, args ...string) ([]byte, error) {
	if name != "git" {
		panic("unexpected command: " + name)
	}
	r.calls = append(r.calls, call{dir: dir, args: append([]string(nil), args...)})
	if len(r.responses) == 0 {
		panic("unexpected command")
	}
	response := r.responses[0]
	r.responses = r.responses[1:]
	return response.output, response.err
}
