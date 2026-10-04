package cli

import (
	"fmt"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/spf13/cobra"
)

func (a App) configuredProjectIgnoreCommand(configPath *string, ignored bool) *cobra.Command {
	use, short := "watch <repository-path>", "Watch a project's pull requests again"
	if ignored {
		use, short = "ignore <repository-path>", "Ignore a project: keep it listed but skip its GitHub requests"
	}
	return &cobra.Command{
		Use:   use,
		Short: short,
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			return a.setConfiguredProjectIgnored(*configPath, args[0], ignored)
		},
	}
}

func (a App) setConfiguredProjectIgnored(configPath, path string, ignored bool) error {
	canonical, err := config.CanonicalizeSourcePath(path)
	if err != nil {
		return fmt.Errorf("resolve project path: %w", err)
	}
	resolvedConfig, err := config.ResolvePath(configPath)
	if err != nil {
		return err
	}
	changed := false
	if err := config.Mutate(resolvedConfig, func(cfg *config.Config) (bool, error) {
		changed, err = config.SetProjectIgnored(cfg, canonical, ignored)
		return changed, err
	}); err != nil {
		return err
	}
	state := "watching"
	if ignored {
		state = "ignoring"
	}
	if !changed {
		state = "already " + state
	}
	_, err = fmt.Fprintf(a.Out, "%s project: %s\n", state, canonical)
	return err
}
