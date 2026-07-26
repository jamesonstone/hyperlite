package cli

import (
	"context"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestResolveColor(t *testing.T) {
	t.Run("auto uses terminal output", func(t *testing.T) {
		t.Setenv("NO_COLOR", "")
		app := App{OutputIsTTY: func() bool { return true }}
		color, err := app.resolveColor("auto")
		if err != nil || !color {
			t.Fatalf("color, err = %t, %v", color, err)
		}
	})

	t.Run("NO_COLOR disables automatic color", func(t *testing.T) {
		t.Setenv("NO_COLOR", "1")
		app := App{OutputIsTTY: func() bool { return true }}
		color, err := app.resolveColor("auto")
		if err != nil || color {
			t.Fatalf("color, err = %t, %v", color, err)
		}
	})

	t.Run("always overrides non terminal output", func(t *testing.T) {
		app := App{OutputIsTTY: func() bool { return false }}
		color, err := app.resolveColor("always")
		if err != nil || !color {
			t.Fatalf("color, err = %t, %v", color, err)
		}
	})

	t.Run("never disables color", func(t *testing.T) {
		app := App{OutputIsTTY: func() bool { return true }}
		color, err := app.resolveColor("never")
		if err != nil || color {
			t.Fatalf("color, err = %t, %v", color, err)
		}
	})
}

func TestRunScanPassesResolvedColorToTerminalOutput(t *testing.T) {
	source := t.TempDir()
	result := model.WorkScan{Errors: []model.ScanError{{Repository: "owner/repo", Stage: "fetch", Message: "network unavailable"}}}
	t.Run("always enables color", func(t *testing.T) {
		var output strings.Builder
		app := App{
			Out:               &output,
			OutputIsTTY:       func() bool { return false },
			workScannerSource: testWorkSnapshotScanner{result: result},
		}
		if err := app.runScan(t.Context(), "", scanOptions{paths: []string{source}, localOnly: true}, "always"); err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(output.String(), terminalRed+"ERROR"+terminalReset) {
			t.Fatalf("terminal output is not colored: %q", output.String())
		}
	})

	t.Run("NO_COLOR disables automatic color", func(t *testing.T) {
		t.Setenv("NO_COLOR", "1")
		var output strings.Builder
		app := App{
			Out:               &output,
			OutputIsTTY:       func() bool { return true },
			workScannerSource: testWorkSnapshotScanner{result: result},
		}
		if err := app.runScan(t.Context(), "", scanOptions{paths: []string{source}, localOnly: true}, "auto"); err != nil {
			t.Fatal(err)
		}
		if strings.Contains(output.String(), "\x1b[") {
			t.Fatalf("terminal output unexpectedly colored: %q", output.String())
		}
	})
}

type testWorkSnapshotScanner struct {
	result model.WorkScan
	err    error
}

func (s testWorkSnapshotScanner) Scan(_ context.Context, _ config.Config, _, _ bool) (model.WorkScan, error) {
	return s.result, s.err
}

func (s testWorkSnapshotScanner) ScanLocal(_ context.Context, _ config.Config, _ bool) (model.WorkScan, error) {
	return s.result, s.err
}
