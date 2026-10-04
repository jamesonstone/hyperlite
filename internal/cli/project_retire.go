package cli

import (
	"fmt"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/spf13/cobra"
)

// retireMissingProjects soft-deletes configured projects whose directory is
// gone so they stop appearing as errors.
func retireMissingProjects(configPath string) ([]config.RetiredProject, error) {
	var retired []config.RetiredProject
	err := config.Mutate(configPath, func(cfg *config.Config) (bool, error) {
		retired = config.RetireMissingProjects(cfg, time.Now())
		return len(retired) > 0, nil
	})
	return retired, err
}

func retiredWarnings(retired []config.RetiredProject) []model.ScanError {
	warnings := make([]model.ScanError, 0, len(retired))
	for _, entry := range retired {
		warnings = append(warnings, model.ScanError{
			RepositoryPath: entry.Path, Stage: "project-retired",
			Message: fmt.Sprintf(
				"removed %s from Hyperlite because its %s; restore with `hyperlite projects restore %s`",
				entry.Path, entry.Reason, entry.Path,
			),
		})
	}
	return warnings
}

func (a App) configuredProjectRestoreCommand(configPath *string) *cobra.Command {
	return &cobra.Command{
		Use:   "restore <repository-path>",
		Short: "Restore a project Hyperlite retired because its directory disappeared",
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			canonical, err := config.CanonicalizeSourcePath(args[0])
			if err != nil {
				return fmt.Errorf("resolve project path: %w", err)
			}
			if !discovery.IsRepositoryRoot(canonical) {
				return fmt.Errorf("project path is not a Git repository root: %s", canonical)
			}
			resolved, err := config.ResolvePath(*configPath)
			if err != nil {
				return err
			}
			if err := config.Mutate(resolved, func(cfg *config.Config) (bool, error) {
				return true, config.RestoreRetiredProject(cfg, canonical)
			}); err != nil {
				return err
			}
			_, err = fmt.Fprintf(a.Out, "restored project: %s\n", canonical)
			return err
		},
	}
}
