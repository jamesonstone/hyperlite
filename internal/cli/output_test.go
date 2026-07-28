package cli

import (
	"errors"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestWriteTerminalDistinguishesDiagnostics(t *testing.T) {
	result := model.ThreadScan{
		Summary:  model.ThreadScanSummary{Projects: 1, Threads: 1, Attention: 1},
		Threads:  []model.Thread{{Title: "R2 storage", Phase: model.ThreadReviewing, Active: true, WhyNow: "Review the deployment boundary"}},
		Errors:   []model.ScanError{{Repository: "owner/repo", Stage: "fetch", Message: "network unavailable"}},
		Warnings: []model.ScanError{{Repository: "owner/repo", Stage: "github", Message: "results truncated"}},
	}
	var output strings.Builder

	if err := writeTerminal(&output, result, false, false); err != nil {
		t.Fatal(err)
	}

	const want = "Hyperlite · 1 project · 1 thread · 1 attention\n" +
		"- R2 storage · reviewing · Review the deployment boundary\n" +
		"ERROR · owner/repo · fetch · network unavailable\n" +
		"WARNING · owner/repo · github · results truncated\n"
	if got := output.String(); got != want {
		t.Fatalf("terminal output = %q, want %q", got, want)
	}
}

func TestWriteTerminalAppliesColorWhenEnabled(t *testing.T) {
	result := model.ThreadScan{
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
	if err := writeTerminal(errorWriter{err: want}, model.ThreadScan{}, false, false); !errors.Is(err, want) {
		t.Fatalf("writeTerminal error = %v, want %v", err, want)
	}
}

type errorWriter struct {
	err error
}

func (w errorWriter) Write([]byte) (int, error) {
	return 0, w.err
}
