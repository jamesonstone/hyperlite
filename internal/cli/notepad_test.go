package cli

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"
)

func TestNotepadCommandsRoundTripVerbatimContent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notepad.md")
	t.Setenv("HYPERLITE_NOTEPAD_PATH", path)
	var output bytes.Buffer
	content := "# Context\n\nDeploy after migration.\n"

	set := App{In: strings.NewReader(content), Out: &output}.notepadSetCommand()
	set.SetArgs([]string{})
	if err := set.Execute(); err == nil || !strings.Contains(err.Error(), "--stdin is required") {
		t.Fatalf("missing --stdin error = %v", err)
	}
	set = App{In: strings.NewReader(content), Out: &output}.notepadSetCommand()
	set.SetArgs([]string{"--stdin"})
	if err := set.Execute(); err != nil {
		t.Fatal(err)
	}

	show := App{Out: &output}.notepadShowCommand()
	if err := show.Execute(); err != nil {
		t.Fatal(err)
	}
	if output.String() != content {
		t.Fatalf("output = %q, want %q", output.String(), content)
	}
}

func TestNotepadCommandDefaultsToShowAndReportsPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notepad.md")
	t.Setenv("HYPERLITE_NOTEPAD_PATH", path)
	var output bytes.Buffer

	command := App{Out: &output}.notepadCommand()
	if err := command.Execute(); err != nil {
		t.Fatal(err)
	}
	if output.Len() != 0 {
		t.Fatalf("empty notepad output = %q", output.String())
	}

	pathCommand := App{Out: &output}.notepadPathCommand()
	if err := pathCommand.Execute(); err != nil {
		t.Fatal(err)
	}
	if output.String() != path+"\n" {
		t.Fatalf("path output = %q", output.String())
	}
}

func TestRootNotepadDoesNotRequireProjectConfiguration(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notepad.md")
	t.Setenv("HYPERLITE_NOTEPAD_PATH", path)
	t.Setenv("HYPERLITE_CONFIG", filepath.Join(t.TempDir(), "invalid.yaml"))
	var output bytes.Buffer

	root := App{Out: &output, Err: &output}.Root()
	root.SetArgs([]string{"notepad"})
	if err := root.Execute(); err != nil {
		t.Fatalf("notepad should be independent of project configuration: %v", err)
	}
}
