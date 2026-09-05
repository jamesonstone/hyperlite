package gitmaint

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
)

const (
	OutcomeUpdated = "updated"
	OutcomeSkipped = "skipped"
	OutcomeFailed  = "failed"

	fetchTimeout = 2 * time.Minute
	gitTimeout   = 15 * time.Second
)

type Result struct {
	Name    string `json:"name"`
	Path    string `json:"path"`
	Base    string `json:"base"`
	Outcome string `json:"outcome"`
	Detail  string `json:"detail"`
}

func UpdateDefaultBranches(
	ctx context.Context,
	runner command.Runner,
	repos []config.Repository,
) []Result {
	results := make([]Result, 0, len(repos))
	for _, repo := range repos {
		results = append(results, updateOne(ctx, runner, repo))
	}
	return results
}

func updateOne(ctx context.Context, runner command.Runner, repo config.Repository) Result {
	result := Result{Name: repo.Name, Path: repo.Path, Base: repo.Base, Outcome: OutcomeFailed}
	if result.Base == "" {
		result.Base = "main"
	}
	remote := repo.Remote
	if remote == "" {
		remote = "origin"
	}
	if _, err := run(ctx, runner, fetchTimeout, repo.Path, "git", "fetch", "--prune", remote); err != nil {
		result.Detail = "fetch: " + err.Error()
		return result
	}
	head, err := runText(ctx, runner, repo.Path, "git", "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		result.Detail = "read HEAD: " + err.Error()
		return result
	}
	if head == result.Base {
		return updateCheckedOut(ctx, runner, repo.Path, remote, result)
	}
	return updateSideBranch(ctx, runner, repo.Path, remote, result)
}

func updateCheckedOut(
	ctx context.Context,
	runner command.Runner,
	path, remote string,
	result Result,
) Result {
	status, err := runText(ctx, runner, path, "git", "status", "--porcelain")
	if err != nil {
		result.Detail = "status: " + err.Error()
		return result
	}
	if status != "" {
		result.Outcome = OutcomeSkipped
		result.Detail = "dirty working tree"
		return result
	}
	upstream := fmt.Sprintf("refs/remotes/%s/%s", remote, result.Base)
	output, err := run(ctx, runner, gitTimeout, path, "git", "merge", "--ff-only", upstream)
	if err != nil {
		result.Outcome = OutcomeSkipped
		result.Detail = "not a fast-forward"
		if message := err.Error(); message != "" {
			result.Detail = message
		}
		return result
	}
	if strings.Contains(strings.ToLower(string(output)), "already up to date") {
		result.Outcome = OutcomeSkipped
		result.Detail = "already up to date"
		return result
	}
	result.Outcome = OutcomeUpdated
	result.Detail = "fast-forwarded " + result.Base
	return result
}

func updateSideBranch(
	ctx context.Context,
	runner command.Runner,
	path, remote string,
	result Result,
) Result {
	localRef := "refs/heads/" + result.Base
	before, _ := runText(ctx, runner, path, "git", "rev-parse", localRef)
	refspec := fmt.Sprintf("refs/heads/%s:refs/heads/%s", result.Base, result.Base)
	if _, err := run(ctx, runner, fetchTimeout, path, "git", "fetch", remote, refspec); err != nil {
		result.Outcome = OutcomeSkipped
		result.Detail = err.Error()
		return result
	}
	after, err := runText(ctx, runner, path, "git", "rev-parse", localRef)
	if err != nil {
		result.Detail = "read " + result.Base + ": " + err.Error()
		return result
	}
	if before == after {
		result.Outcome = OutcomeSkipped
		result.Detail = "already up to date"
		return result
	}
	result.Outcome = OutcomeUpdated
	result.Detail = "updated " + result.Base
	return result
}

func runText(
	ctx context.Context,
	runner command.Runner,
	dir string,
	name string,
	args ...string,
) (string, error) {
	output, err := run(ctx, runner, gitTimeout, dir, name, args...)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(output)), nil
}

func run(
	ctx context.Context,
	runner command.Runner,
	timeout time.Duration,
	dir, name string,
	args ...string,
) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	return runner.Run(ctx, dir, name, args...)
}
