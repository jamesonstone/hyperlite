package cli

import (
	"encoding/json"
	"fmt"
	"io"

	"github.com/jamesonstone/hyperlite/internal/notepad"
	"github.com/spf13/cobra"
)

func (a App) notepadCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "notepad",
		Short: "Read Hyperlite's local pinned and daily notes",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return a.showNotepad("", false)
		},
	}
	command.AddCommand(
		a.notepadShowCommand(),
		a.notepadSetCommand(),
		a.notepadPathCommand(),
		a.notepadIndexCommand(),
	)
	return command
}

func (a App) notepadShowCommand() *cobra.Command {
	var date string
	var jsonOutput bool
	command := &cobra.Command{
		Use:   "show",
		Short: "Print the pinned note or one daily note",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return a.showNotepad(date, jsonOutput)
		},
	}
	command.Flags().StringVar(&date, "date", "", "daily note date in YYYY-MM-DD form")
	command.Flags().BoolVar(&jsonOutput, "json", false, "emit the note document as JSON")
	return command
}

func (a App) showNotepad(date string, jsonOutput bool) error {
	store := notepad.Store{}
	var document notepad.Document
	var err error
	if date == "" {
		document, err = store.LoadPinned()
	} else {
		document, err = store.LoadDaily(date)
	}
	if err != nil {
		return err
	}
	if jsonOutput {
		return json.NewEncoder(a.Out).Encode(document)
	}
	_, err = io.WriteString(a.Out, document.Content)
	return err
}

func (a App) notepadSetCommand() *cobra.Command {
	var fromStdin bool
	var date string
	var jsonOutput bool
	command := &cobra.Command{
		Use:   "set",
		Short: "Replace the pinned note or one daily note from stdin",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			if !fromStdin {
				return usageError{fmt.Errorf("--stdin is required")}
			}
			contents, err := io.ReadAll(io.LimitReader(a.input(), notepad.MaxBytes+1))
			if err != nil {
				return fmt.Errorf("read note: %w", err)
			}
			if len(contents) > notepad.MaxBytes {
				return usageError{fmt.Errorf("note must be at most %d bytes", notepad.MaxBytes)}
			}
			store := notepad.Store{}
			var document notepad.Document
			if date == "" {
				document, err = store.WritePinned(string(contents))
			} else {
				document, err = store.WriteDaily(date, string(contents))
			}
			if err != nil {
				return err
			}
			if jsonOutput {
				return json.NewEncoder(a.Out).Encode(document)
			}
			return nil
		},
	}
	command.Flags().BoolVar(&fromStdin, "stdin", false, "read the note from stdin")
	command.Flags().StringVar(&date, "date", "", "daily note date in YYYY-MM-DD form")
	command.Flags().BoolVar(&jsonOutput, "json", false, "emit the saved note document as JSON")
	return command
}

func (a App) notepadPathCommand() *cobra.Command {
	var date string
	command := &cobra.Command{
		Use:   "path",
		Short: "Print the pinned or daily note path",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			path, err := (notepad.Store{}).Path(date)
			if err != nil {
				return err
			}
			_, err = fmt.Fprintln(a.Out, path)
			return err
		},
	}
	command.Flags().StringVar(&date, "date", "", "daily note date in YYYY-MM-DD form")
	return command
}

func (a App) notepadIndexCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "index",
		Short: "Print note documents for asynchronous search indexing",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			documents, err := (notepad.Store{}).Documents()
			if err != nil {
				return err
			}
			return json.NewEncoder(a.Out).Encode(documents)
		},
	}
}
