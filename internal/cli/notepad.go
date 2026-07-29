package cli

import (
	"fmt"
	"io"

	"github.com/jamesonstone/hyperlite/internal/notepad"
	"github.com/spf13/cobra"
)

func (a App) notepadCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "notepad",
		Short: "Read Hyperlite's local notepad",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return a.showNotepad()
		},
	}
	command.AddCommand(a.notepadShowCommand(), a.notepadSetCommand(), a.notepadPathCommand())
	return command
}

func (a App) notepadShowCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "show",
		Short: "Print the local notepad",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return a.showNotepad()
		},
	}
}

func (a App) showNotepad() error {
	document, err := (notepad.Store{}).Load()
	if err != nil {
		return err
	}
	_, err = io.WriteString(a.Out, document.Content)
	return err
}

func (a App) notepadSetCommand() *cobra.Command {
	var fromStdin bool
	command := &cobra.Command{
		Use:   "set",
		Short: "Replace the local notepad from stdin",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			if !fromStdin {
				return usageError{fmt.Errorf("--stdin is required")}
			}
			contents, err := io.ReadAll(io.LimitReader(a.input(), notepad.MaxBytes+1))
			if err != nil {
				return fmt.Errorf("read notepad: %w", err)
			}
			if len(contents) > notepad.MaxBytes {
				return usageError{fmt.Errorf("notepad must be at most %d bytes", notepad.MaxBytes)}
			}
			_, err = (notepad.Store{}).Write(string(contents))
			return err
		},
	}
	command.Flags().BoolVar(&fromStdin, "stdin", false, "read the notepad from stdin")
	return command
}

func (a App) notepadPathCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "path",
		Short: "Print the local notepad path",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			path, err := notepad.ResolvePath()
			if err != nil {
				return err
			}
			_, err = fmt.Fprintln(a.Out, path)
			return err
		},
	}
}
