package cli

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/prindex"
)

func TestRunPullRequestsSelectsLocalStaleAndForceModes(t *testing.T) {
	project := t.TempDir()
	configPath := filepath.Join(t.TempDir(), "config.yaml")
	contents := []byte("version: 2\nprojects:\n  - path: " + project + "\n")
	if err := os.WriteFile(configPath, contents, 0o600); err != nil {
		t.Fatal(err)
	}
	scanner := &recordingProjectPullRequestScanner{result: model.ProjectPullRequestScan{
		SchemaVersion: model.ProjectPullRequestScanSchemaVersion,
		Projects:      []model.ProjectPullRequests{},
		Errors:        []model.ScanError{}, Warnings: []model.ScanError{},
	}}
	var output bytes.Buffer
	app := App{Out: &output, pullRequestScannerSource: scanner}
	for _, test := range []struct {
		options pullRequestOptions
		mode    prindex.RefreshMode
	}{
		{pullRequestOptions{localOnly: true, jsonOutput: true}, prindex.RefreshLocal},
		{pullRequestOptions{jsonOutput: true}, prindex.RefreshStale},
		{pullRequestOptions{force: true, jsonOutput: true}, prindex.RefreshForce},
	} {
		output.Reset()
		if err := app.runPullRequests(t.Context(), configPath, test.options); err != nil {
			t.Fatal(err)
		}
		if scanner.modes[len(scanner.modes)-1] != test.mode {
			t.Fatalf("modes = %#v", scanner.modes)
		}
	}
}

func TestRunPullRequestsRejectsLocalForceCombination(t *testing.T) {
	err := (App{}).runPullRequests(
		t.Context(), "", pullRequestOptions{localOnly: true, force: true},
	)
	if err == nil || ExitCode(err) != 2 {
		t.Fatalf("err = %v", err)
	}
}

type recordingProjectPullRequestScanner struct {
	modes  []prindex.RefreshMode
	result model.ProjectPullRequestScan
}

func (s *recordingProjectPullRequestScanner) Scan(
	_ context.Context,
	_ config.Config,
	mode prindex.RefreshMode,
) (model.ProjectPullRequestScan, error) {
	s.modes = append(s.modes, mode)
	return s.result, nil
}
