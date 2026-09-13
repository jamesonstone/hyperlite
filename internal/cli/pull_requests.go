package cli

import (
	"context"
	"encoding/json"
	"fmt"
	"io"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/prindex"
	"github.com/spf13/cobra"
)

type pullRequestOptions struct {
	localOnly  bool
	force      bool
	activity   bool
	jsonOutput bool
}

func (a App) pullRequestsCommand(configPath *string) *cobra.Command {
	var options pullRequestOptions
	command := &cobra.Command{
		Use:   "pull-requests",
		Short: "List open pull requests across configured projects",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return a.runPullRequests(cmd.Context(), *configPath, options)
		},
	}
	command.Flags().BoolVar(&options.localOnly, "local", false, "read cached pull requests without GitHub")
	command.Flags().BoolVar(&options.force, "force", false, "refresh every resolved project regardless of cache age")
	command.Flags().BoolVar(&options.activity, "activity", false, "poll only running workflow activity when the quota governor allows")
	command.Flags().BoolVar(&options.jsonOutput, "json", false, "emit JSON only")
	return command
}

func (a App) runPullRequests(
	ctx context.Context,
	configPath string,
	options pullRequestOptions,
) error {
	exclusive := 0
	for _, flag := range []bool{options.localOnly, options.force, options.activity} {
		if flag {
			exclusive++
		}
	}
	if exclusive > 1 {
		return usageError{fmt.Errorf("--local, --force, and --activity are mutually exclusive")}
	}
	path, err := config.EnsureDefaultConfig(configPath)
	if err != nil {
		return err
	}
	cfg, err := config.Load(path)
	if err != nil {
		return err
	}
	cfg.Sources = append([]config.Source(nil), cfg.Projects...)
	cfg.Repositories = nil
	mode := prindex.RefreshStale
	switch {
	case options.localOnly:
		mode = prindex.RefreshLocal
	case options.force:
		mode = prindex.RefreshForce
	case options.activity:
		mode = prindex.RefreshActivity
	}
	result, err := a.pullRequestScanner().Scan(ctx, cfg, mode)
	if err != nil {
		return err
	}
	if options.jsonOutput {
		return json.NewEncoder(a.Out).Encode(result)
	}
	return writePullRequests(a.Out, result)
}

func writePullRequests(out io.Writer, result model.ProjectPullRequestScan) error {
	count := 0
	for _, project := range result.Projects {
		count += len(project.PullRequests)
	}
	if _, err := fmt.Fprintf(out, "Open PRs · %d\n", count); err != nil {
		return err
	}
	for _, project := range result.Projects {
		for _, pullRequest := range project.PullRequests {
			state := "ready"
			if pullRequest.IsDraft {
				state = "draft"
			}
			if _, err := fmt.Fprintf(
				out, "- %s #%d · %s · %s\n",
				project.Name, pullRequest.Number, state, pullRequest.Title,
			); err != nil {
				return err
			}
		}
		if project.Status == model.ProjectPullRequestsUnavailable ||
			project.Status == model.ProjectPullRequestsCached {
			if _, err := fmt.Fprintf(
				out, "- %s · %s · %s\n",
				project.Name, project.Status, project.Message,
			); err != nil {
				return err
			}
		}
	}
	return nil
}
