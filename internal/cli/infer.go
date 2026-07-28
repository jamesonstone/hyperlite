package cli

import (
	"encoding/json"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/spf13/cobra"
)

func (a App) inferCommand(configPath *string) *cobra.Command {
	var jsonOutput bool
	command := &cobra.Command{
		Use:   "infer",
		Short: "Enrich cached threads with the configured local model",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			cfg, err := loadSelectedConfig(*configPath)
			if err != nil {
				return err
			}
			result, err := a.workScanner().Infer(cmd.Context(), cfg)
			if err != nil {
				return err
			}
			if jsonOutput {
				return json.NewEncoder(a.Out).Encode(result)
			}
			colorMode, _ := cmd.Flags().GetString("color")
			color, err := a.resolveColor(colorMode)
			if err != nil {
				return err
			}
			return writeTerminal(a.Out, result, false, color)
		},
	}
	command.Flags().BoolVar(&jsonOutput, "json", false, "emit JSON only")
	return command
}

func loadSelectedConfig(configPath string) (config.Config, error) {
	path, err := config.EnsureDefaultConfig(configPath)
	if err != nil {
		return config.Config{}, err
	}
	cfg, err := config.Load(path)
	if err != nil {
		return config.Config{}, err
	}
	cfg.Sources = append([]config.Source(nil), cfg.Projects...)
	cfg.Repositories = nil
	return cfg, nil
}
