package cli

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/prindex"
	"github.com/jamesonstone/hyperlite/internal/workscan"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)

var (
	Version = "dev"
	Commit  = "unknown"
	Date    = "unknown"
)

type App struct {
	In                              io.Reader
	Out                             io.Writer
	Err                             io.Writer
	Runner                          command.Runner
	InputIsTTY                      func() bool
	OutputIsTTY                     func() bool
	workScannerSource               workSnapshotScanner
	pullRequestScannerSource        projectPullRequestScanner
	configuredProjectPrompterSource configuredProjectPrompter
}

type workSnapshotScanner interface {
	Scan(context.Context, config.Config, bool, bool) (model.ThreadScan, error)
	ScanLocal(context.Context, config.Config, bool) (model.ThreadScan, error)
	Infer(context.Context, config.Config) (model.ThreadScan, error)
}

type projectPullRequestScanner interface {
	Scan(
		context.Context,
		config.Config,
		prindex.RefreshMode,
	) (model.ProjectPullRequestScan, error)
}

type huhPrompter struct {
	input  io.Reader
	output io.Writer
}

func New() *cobra.Command { return newApp().Root() }

func newApp() App {
	return App{
		In: os.Stdin, Out: os.Stdout, Err: os.Stderr, Runner: command.ExecRunner{},
		InputIsTTY:  func() bool { return term.IsTerminal(int(os.Stdin.Fd())) },
		OutputIsTTY: func() bool { return term.IsTerminal(int(os.Stdout.Fd())) },
	}
}

func (a App) Root() *cobra.Command {
	var configPath string
	var colorMode string
	var options scanOptions
	root := &cobra.Command{
		Use:           "hyperlite",
		Short:         "Fast status for active Git work",
		SilenceErrors: true,
		SilenceUsage:  true,
		Args:          noArgs,
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			if cmd.Name() == "version" ||
				strings.HasPrefix(cmd.CommandPath(), "hyperlite notepad") ||
				(cmd.Name() == "scan" && len(args) > 0) {
				return nil
			}
			_, err := config.EnsureDefaultConfig(configPath)
			return err
		},
		RunE: func(cmd *cobra.Command, _ []string) error {
			return a.runScan(cmd.Context(), configPath, options, colorMode)
		},
	}
	root.PersistentFlags().StringVar(&configPath, "config", "", "Hyperlite configuration file path")
	root.PersistentFlags().StringVar(&colorMode, "color", "auto", "color output: auto, always, or never")
	addScanFlags(root, &options)
	root.SetFlagErrorFunc(func(_ *cobra.Command, err error) error { return usageError{err} })
	root.AddCommand(
		a.scanCommand(&configPath),
		a.inferCommand(&configPath),
		a.notepadCommand(),
		a.threadCommand(),
		a.pullRequestsCommand(&configPath),
		a.configuredProjectsCommand(&configPath),
		versionCommand(a.Out),
	)
	return root
}

func versionCommand(out io.Writer) *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Show Hyperlite version information",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			_, err := fmt.Fprintf(out, "hyperlite %s (%s, %s)\n", Version, Commit, Date)
			return err
		},
	}
}

func (a App) workScanner() workSnapshotScanner {
	if a.workScannerSource != nil {
		return a.workScannerSource
	}
	return workscan.New(a.Runner)
}

func (a App) pullRequestScanner() projectPullRequestScanner {
	if a.pullRequestScannerSource != nil {
		return a.pullRequestScannerSource
	}
	return prindex.New(a.Runner)
}

func (a App) resolveColor(mode string) (bool, error) {
	switch mode {
	case "", "auto":
		return a.outputIsTTY() && os.Getenv("NO_COLOR") == "", nil
	case "always":
		return true, nil
	case "never":
		return false, nil
	default:
		return false, usageError{fmt.Errorf("--color must be auto, always, or never: %q", mode)}
	}
}

func (a App) input() io.Reader {
	if a.In != nil {
		return a.In
	}
	return os.Stdin
}

func (a App) inputIsTTY() bool  { return a.InputIsTTY != nil && a.InputIsTTY() }
func (a App) outputIsTTY() bool { return a.OutputIsTTY != nil && a.OutputIsTTY() }

type usageError struct{ error }

func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	var usage usageError
	if errors.As(err, &usage) || strings.Contains(err.Error(), "unknown command") {
		return 2
	}
	return 1
}

func noArgs(cmd *cobra.Command, args []string) error {
	if len(args) != 0 {
		return usageError{fmt.Errorf("%s accepts no arguments", cmd.CommandPath())}
	}
	return nil
}

func pluralSuffix(count int) string {
	if count == 1 {
		return ""
	}
	return "s"
}
