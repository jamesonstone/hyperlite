package gitmaint

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestUpdateDefaultBranchesFastForwardsCheckedOutBase(t *testing.T) {
	runner := &scriptedRunner{responses: []scriptedResponse{
		{args: "git fetch --prune origin", output: ""},
		{args: "git rev-parse --abbrev-ref HEAD", output: "main\n"},
		{args: "git status --porcelain", output: ""},
		{args: "git merge --ff-only refs/remotes/origin/main", output: "Updating abc..def\n"},
	}}
	results := UpdateDefaultBranches(t.Context(), runner, []config.Repository{{
		Name: "kit", Path: "/repo/kit", Base: "main", Remote: "origin",
	}})
	if len(results) != 1 || results[0].Outcome != OutcomeUpdated {
		t.Fatalf("results = %#v", results)
	}
	if results[0].Detail != "fast-forwarded main" {
		t.Fatalf("detail = %q", results[0].Detail)
	}
}

func TestUpdateDefaultBranchesSkipsDirtyCheckedOutBase(t *testing.T) {
	runner := &scriptedRunner{responses: []scriptedResponse{
		{args: "git fetch --prune origin", output: ""},
		{args: "git rev-parse --abbrev-ref HEAD", output: "main\n"},
		{args: "git status --porcelain", output: " M README.md\n"},
	}}
	results := UpdateDefaultBranches(t.Context(), runner, []config.Repository{{
		Name: "kit", Path: "/repo/kit", Base: "main", Remote: "origin",
	}})
	if results[0].Outcome != OutcomeSkipped || results[0].Detail != "dirty working tree" {
		t.Fatalf("results = %#v", results)
	}
}

func TestUpdateDefaultBranchesUpdatesUnrelatedCheckout(t *testing.T) {
	runner := &scriptedRunner{responses: []scriptedResponse{
		{args: "git fetch --prune origin", output: ""},
		{args: "git rev-parse --abbrev-ref HEAD", output: "GH-64\n"},
		{args: "git rev-parse refs/heads/main", output: "aaa\n"},
		{args: "git fetch origin refs/heads/main:refs/heads/main", output: ""},
		{args: "git rev-parse refs/heads/main", output: "bbb\n"},
	}}
	results := UpdateDefaultBranches(t.Context(), runner, []config.Repository{{
		Name: "kit", Path: "/repo/kit", Base: "main", Remote: "origin",
	}})
	if results[0].Outcome != OutcomeUpdated {
		t.Fatalf("results = %#v", results)
	}
}

func TestUpdateDefaultBranchesSkipsCheckedOutRefspec(t *testing.T) {
	runner := &scriptedRunner{responses: []scriptedResponse{
		{args: "git fetch --prune origin", output: ""},
		{args: "git rev-parse --abbrev-ref HEAD", output: "feature\n"},
		{args: "git rev-parse refs/heads/main", output: "aaa\n"},
		{
			args: "git fetch origin refs/heads/main:refs/heads/main",
			err:  errors.New("refusing to fetch into branch 'refs/heads/main' checked out at"),
		},
	}}
	results := UpdateDefaultBranches(t.Context(), runner, []config.Repository{{
		Name: "kit", Path: "/repo/kit", Base: "main", Remote: "origin",
	}})
	if results[0].Outcome != OutcomeSkipped {
		t.Fatalf("results = %#v", results)
	}
	if !strings.Contains(results[0].Detail, "checked out") {
		t.Fatalf("detail = %q", results[0].Detail)
	}
}

func TestUpdateDefaultBranchesReportsFetchFailure(t *testing.T) {
	runner := &scriptedRunner{responses: []scriptedResponse{
		{args: "git fetch --prune origin", err: errors.New("could not resolve host")},
	}}
	results := UpdateDefaultBranches(t.Context(), runner, []config.Repository{{
		Name: "kit", Path: "/repo/kit", Base: "main", Remote: "origin",
	}})
	if results[0].Outcome != OutcomeFailed || !strings.Contains(results[0].Detail, "fetch:") {
		t.Fatalf("results = %#v", results)
	}
}

type scriptedResponse struct {
	args   string
	output string
	err    error
}

type scriptedRunner struct {
	responses []scriptedResponse
}

func (r *scriptedRunner) Run(_ context.Context, _, name string, args ...string) ([]byte, error) {
	got := strings.TrimSpace(name + " " + strings.Join(args, " "))
	if len(r.responses) == 0 {
		return nil, errors.New("unexpected git command: " + got)
	}
	next := r.responses[0]
	r.responses = r.responses[1:]
	if next.args != got {
		return nil, errors.New("expected " + next.args + ", got " + got)
	}
	return []byte(next.output), next.err
}
