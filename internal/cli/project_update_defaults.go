package cli

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jamesonstone/hyperlite/internal/gitmaint"
	"github.com/spf13/cobra"
)

type defaultBranchUpdateList struct {
	Results []gitmaint.Result `json:"results"`
}

func (a App) configuredProjectUpdateDefaultsCommand(configPath *string) *cobra.Command {
	var jsonOutput bool
	command := &cobra.Command{
		Use:   "update-defaults",
		Short: "Fast-forward configured default branches when Git allows",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return a.runConfiguredProjectUpdateDefaults(cmd.Context(), *configPath, jsonOutput)
		},
	}
	command.Flags().BoolVar(&jsonOutput, "json", false, "emit JSON only")
	return command
}

func (a App) runConfiguredProjectUpdateDefaults(
	ctx context.Context,
	configPath string,
	jsonOutput bool,
) error {
	repos, err := a.discoverConfiguredRepositories(ctx, configPath)
	if err != nil {
		return err
	}
	list := defaultBranchUpdateList{
		Results: gitmaint.UpdateDefaultBranches(ctx, a.commandRunner(), repos),
	}
	if jsonOutput {
		return json.NewEncoder(a.Out).Encode(list)
	}
	for _, result := range list.Results {
		if _, err := fmt.Fprintf(
			a.Out, "%s\t%s\t%s\t%s\n",
			result.Name, result.Outcome, result.Base, result.Detail,
		); err != nil {
			return err
		}
	}
	return nil
}
