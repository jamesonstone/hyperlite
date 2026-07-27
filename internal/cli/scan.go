package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/spf13/cobra"
)

type scanOptions struct {
	paths       []string
	noRefresh   bool
	includeIdle bool
	jsonOutput  bool
	localOnly   bool
}

func addScanFlags(command *cobra.Command, options *scanOptions) {
	command.Flags().BoolVar(&options.jsonOutput, "json", false, "emit JSON only")
	command.Flags().BoolVar(&options.noRefresh, "no-refresh", false, "skip git fetch")
	command.Flags().BoolVar(&options.localOnly, "local", false, "skip GitHub pull request lookup")
	command.Flags().BoolVar(&options.includeIdle, "include-idle", false, "show projects with no active work")
}

func (a App) scanCommand(configPath *string) *cobra.Command {
	var options scanOptions
	command := &cobra.Command{
		Use:   "scan [path...]",
		Short: "Scan selected projects or supplied paths",
		Args:  cobra.ArbitraryArgs,
		RunE: func(cmd *cobra.Command, paths []string) error {
			options.paths = paths
			colorMode, _ := cmd.Flags().GetString("color")
			return a.runScan(cmd.Context(), *configPath, options, colorMode)
		},
	}
	addScanFlags(command, &options)
	return command
}

func (a App) runScan(ctx context.Context, configPath string, options scanOptions, colorMode string) error {
	color, err := a.resolveColor(colorMode)
	if err != nil {
		return err
	}
	if len(options.paths) > 0 {
		if configPath != "" {
			return usageError{errors.New("--config cannot be used with path arguments")}
		}
		cfg, err := config.ForSources(options.paths)
		if err != nil {
			return err
		}
		return a.writeScan(ctx, cfg, options, color)
	}
	path, err := config.EnsureDefaultConfig(configPath)
	if err != nil {
		return err
	}
	cfg, err := config.Load(path)
	if errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("%w; run hyperlite projects to select projects", err)
	}
	if err != nil {
		return err
	}
	cfg.Sources = append([]config.Source(nil), cfg.Projects...)
	cfg.Repositories = nil
	return a.writeScan(ctx, cfg, options, color)
}

func (a App) writeScan(ctx context.Context, cfg config.Config, options scanOptions, color bool) error {
	var (
		result model.WorkScan
		err    error
	)
	if options.localOnly {
		result, err = a.workScanner().ScanLocal(ctx, cfg, options.includeIdle)
	} else {
		result, err = a.workScanner().Scan(ctx, cfg, !options.noRefresh, options.includeIdle)
	}
	if err != nil {
		return err
	}
	if options.jsonOutput {
		encoder := json.NewEncoder(a.Out)
		return encoder.Encode(result)
	}
	return writeTerminal(a.Out, result, options.includeIdle, color)
}
