package cli

import (
	"fmt"
	"io"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func writeTerminal(out io.Writer, result model.WorkScan, includeIdle bool) error {
	if _, err := fmt.Fprintf(out, "Hyperlite · %d project%s · %d active item%s\n", result.Summary.Projects, pluralSuffix(result.Summary.Projects), result.Summary.WorkItems, pluralSuffix(result.Summary.WorkItems)); err != nil {
		return err
	}
	for _, item := range result.Items {
		if !includeIdle && item.State == model.WorkIdle {
			continue
		}
		status := string(item.State)
		if item.PullRequest != nil {
			status = fmt.Sprintf("PR #%d", item.PullRequest.Number)
		}
		if _, err := fmt.Fprintf(out, "- %s · %s · %s\n", item.Repository, status, item.RepositoryPath); err != nil {
			return err
		}
	}
	for _, diagnostic := range append(append([]model.ScanError{}, result.Errors...), result.Warnings...) {
		parts := []string{diagnostic.Repository, diagnostic.Stage, diagnostic.Message}
		if _, err := fmt.Fprintf(out, "! %s\n", strings.TrimSpace(strings.Join(parts, " · "))); err != nil {
			return err
		}
	}
	return nil
}
