package cli

import (
	"errors"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestWriteTerminalDistinguishesDiagnostics(t *testing.T) {
	result := model.WorkScan{
		Summary:  model.WorkScanSummary{Projects: 1, WorkItems: 1},
		Errors:   []model.ScanError{{Repository: "owner/repo", Stage: "fetch", Message: "network unavailable"}},
		Warnings: []model.ScanError{{Repository: "owner/repo", Stage: "github", Message: "results truncated"}},
	}
	var output strings.Builder

	if err := writeTerminal(&output, result, false, false); err != nil {
		t.Fatal(err)
	}

	const want = "Hyperlite · 1 project · 1 active item\n" +
		"ERROR · owner/repo · fetch · network unavailable\n" +
		"WARNING · owner/repo · github · results truncated\n"
	if got := output.String(); got != want {
		t.Fatalf("terminal output = %q, want %q", got, want)
	}
}

func TestWriteTerminalAppliesColorWhenEnabled(t *testing.T) {
	result := model.WorkScan{
		Errors:   []model.ScanError{{Repository: "owner/repo", Stage: "fetch", Message: "network unavailable"}},
		Warnings: []model.ScanError{{Repository: "owner/repo", Stage: "github", Message: "results truncated"}},
	}
	var output strings.Builder

	if err := writeTerminal(&output, result, false, true); err != nil {
		t.Fatal(err)
	}
	got := output.String()
	for _, want := range []string{
		terminalCyan + "Hyperlite" + terminalReset,
		terminalRed + "ERROR" + terminalReset,
		terminalYellow + "WARNING" + terminalReset,
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("terminal output %q does not contain %q", got, want)
		}
	}
}

func TestWriteTerminalPropagatesWriterError(t *testing.T) {
	want := errors.New("write failed")
	if err := writeTerminal(errorWriter{err: want}, model.WorkScan{}, false, false); !errors.Is(err, want) {
		t.Fatalf("writeTerminal error = %v, want %v", err, want)
	}
}

type errorWriter struct {
	err error
}

func (w errorWriter) Write([]byte) (int, error) {
	return 0, w.err
}
