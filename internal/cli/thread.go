package cli

import (
	"fmt"
	"io"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/threadstate"
	"github.com/spf13/cobra"
)

const maxThreadNoteBytes = 16 * 1024

func (a App) threadCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "thread",
		Short: "Update local inferred-thread presentation state",
		Args:  noArgs,
	}
	command.AddCommand(a.threadSeenCommand(), a.threadNoteCommand())
	return command
}

func (a App) threadSeenCommand() *cobra.Command {
	var revision string
	command := &cobra.Command{
		Use:   "seen <thread-id>",
		Short: "Mark attention through an exact thread revision as seen",
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			normalizedRevision := strings.TrimSpace(revision)
			if normalizedRevision == "" {
				return usageError{fmt.Errorf("--revision is required")}
			}
			err := (threadstate.Store{}).Mutate(func(state *threadstate.State) error {
				return threadstate.MarkSeen(state, args[0], normalizedRevision)
			})
			if err != nil {
				return err
			}
			_, err = fmt.Fprintf(a.Out, "marked thread %s seen through %s\n", args[0], normalizedRevision)
			return err
		},
	}
	command.Flags().StringVar(&revision, "revision", "", "exact material revision displayed by the client")
	return command
}

func (a App) threadNoteCommand() *cobra.Command {
	var fromStdin bool
	command := &cobra.Command{
		Use:   "note <thread-id>",
		Short: "Replace a thread's optional local note from stdin",
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			if !fromStdin {
				return usageError{fmt.Errorf("--stdin is required")}
			}
			contents, err := io.ReadAll(io.LimitReader(a.input(), maxThreadNoteBytes+1))
			if err != nil {
				return fmt.Errorf("read thread note: %w", err)
			}
			if len(contents) > maxThreadNoteBytes {
				return usageError{fmt.Errorf("thread note must be at most %d bytes", maxThreadNoteBytes)}
			}
			note := strings.TrimSpace(string(contents))
			err = (threadstate.Store{}).Mutate(func(state *threadstate.State) error {
				return threadstate.SetNote(state, args[0], note)
			})
			if err != nil {
				return err
			}
			_, err = fmt.Fprintf(a.Out, "updated note for thread %s\n", args[0])
			return err
		},
	}
	command.Flags().BoolVar(&fromStdin, "stdin", false, "read the note from stdin")
	return command
}
