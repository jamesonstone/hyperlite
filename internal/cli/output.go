package cli

import (
	"fmt"
	"io"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/model"
)

const (
	terminalReset  = "\x1b[0m"
	terminalCyan   = "\x1b[36m"
	terminalRed    = "\x1b[31m"
	terminalYellow = "\x1b[33m"
)

func writeTerminal(out io.Writer, result model.WorkScan, includeIdle, color bool) error {
	title := terminalText("Hyperlite", terminalCyan, color)
	if _, err := fmt.Fprintf(out, "%s · %d project%s · %d active item%s\n", title, result.Summary.Projects, pluralSuffix(result.Summary.Projects), result.Summary.WorkItems, pluralSuffix(result.Summary.WorkItems)); err != nil {
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
	for _, diagnostic := range result.Errors {
		if err := writeTerminalDiagnostic(out, "ERROR", terminalRed, diagnostic, color); err != nil {
			return err
		}
	}
	for _, diagnostic := range result.Warnings {
		if err := writeTerminalDiagnostic(out, "WARNING", terminalYellow, diagnostic, color); err != nil {
			return err
		}
	}
	return nil
}

func writeTerminalDiagnostic(out io.Writer, label, style string, diagnostic model.ScanError, color bool) error {
	parts := []string{diagnostic.Repository, diagnostic.Stage, diagnostic.Message}
	_, err := fmt.Fprintf(out, "%s · %s\n", terminalText(label, style, color), strings.TrimSpace(strings.Join(parts, " · ")))
	return err
}

func terminalText(text, style string, color bool) string {
	if !color {
		return text
	}
	return style + text + terminalReset
}
