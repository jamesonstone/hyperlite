package cli

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"github.com/jamesonstone/hyperlite/internal/pinboard"
	"github.com/spf13/cobra"
)

func (a App) pinboardCommand() *cobra.Command {
	command := &cobra.Command{
		Use:   "pinboard",
		Short: "Read and update Hyperlite's private notes pinboard",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return a.showPinboard()
		},
	}
	command.AddCommand(a.pinboardShowCommand(), a.pinboardMutateCommand())
	return command
}

func (a App) pinboardShowCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "show",
		Short: "Print the private pinboard snapshot as JSON",
		Args:  noArgs,
		RunE:  func(_ *cobra.Command, _ []string) error { return a.showPinboard() },
	}
}

func (a App) showPinboard() error {
	snapshot, err := (pinboard.Store{}).Load()
	if err != nil {
		return err
	}
	return json.NewEncoder(a.Out).Encode(snapshot)
}

func (a App) pinboardMutateCommand() *cobra.Command {
	var fromStdin bool
	command := &cobra.Command{
		Use:   "mutate",
		Short: "Apply one typed private pinboard mutation from JSON stdin",
		Args:  noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			if !fromStdin {
				return usageError{fmt.Errorf("--stdin is required")}
			}
			contents, err := io.ReadAll(io.LimitReader(a.input(), pinboard.MaxMutationBytes+1))
			if err != nil {
				return fmt.Errorf("read pinboard mutation: %w", err)
			}
			if len(contents) > pinboard.MaxMutationBytes {
				return usageError{fmt.Errorf("pinboard mutation exceeds the %d-byte limit", pinboard.MaxMutationBytes)}
			}
			decoder := json.NewDecoder(bytes.NewReader(contents))
			decoder.DisallowUnknownFields()
			var mutation pinboard.Mutation
			if err := decoder.Decode(&mutation); err != nil {
				return usageError{fmt.Errorf("decode pinboard mutation: %w", err)}
			}
			var extra any
			if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
				if err == nil {
					return usageError{errors.New("pinboard mutation contains multiple JSON values")}
				}
				return usageError{fmt.Errorf("decode pinboard mutation: %w", err)}
			}
			snapshot, err := (pinboard.Store{}).Mutate(mutation)
			if err != nil {
				return err
			}
			return json.NewEncoder(a.Out).Encode(snapshot)
		},
	}
	command.Flags().BoolVar(&fromStdin, "stdin", false, "read one mutation as JSON from stdin")
	return command
}
