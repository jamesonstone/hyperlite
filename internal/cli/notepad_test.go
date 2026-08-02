package cli

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/notepad"
)

func TestNotepadCommandsRoundTripPinnedAndDailyContent(t *testing.T) {
	root := filepath.Join(t.TempDir(), "notes")
	t.Setenv("HYPERLITE_NOTES_PATH", root)
	var output bytes.Buffer
	pinned := "# Context\n\nDeploy after migration.\n"
	daily := "# 2026-08-02\n\nShipped the migration.\n"

	set := App{In: strings.NewReader(pinned), Out: &output}.notepadSetCommand()
	if err := set.Execute(); err == nil || !strings.Contains(err.Error(), "--stdin is required") {
		t.Fatalf("missing --stdin error = %v", err)
	}
	set = App{In: strings.NewReader(pinned), Out: &output}.notepadSetCommand()
	set.SetArgs([]string{"--stdin"})
	if err := set.Execute(); err != nil {
		t.Fatal(err)
	}
	set = App{In: strings.NewReader(daily), Out: &output}.notepadSetCommand()
	set.SetArgs([]string{"--stdin", "--date", "2026-08-02"})
	if err := set.Execute(); err != nil {
		t.Fatal(err)
	}

	show := App{Out: &output}.notepadShowCommand()
	if err := show.Execute(); err != nil {
		t.Fatal(err)
	}
	if output.String() != pinned {
		t.Fatalf("pinned output = %q, want %q", output.String(), pinned)
	}
	output.Reset()
	show = App{Out: &output}.notepadShowCommand()
	show.SetArgs([]string{"--date", "2026-08-02"})
	if err := show.Execute(); err != nil {
		t.Fatal(err)
	}
	if output.String() != daily {
		t.Fatalf("daily output = %q, want %q", output.String(), daily)
	}
	output.Reset()
	show = App{Out: &output}.notepadShowCommand()
	show.SetArgs([]string{"--date", "2026-08-02", "--json"})
	if err := show.Execute(); err != nil {
		t.Fatal(err)
	}
	var document notepad.Document
	if err := json.Unmarshal(output.Bytes(), &document); err != nil {
		t.Fatal(err)
	}
	if document.Kind != notepad.KindDaily || document.Content != daily || !document.Exists {
		t.Fatalf("daily JSON document = %#v", document)
	}
}

func TestNotepadCommandDefaultsToPinnedAndReportsExactPaths(t *testing.T) {
	root := filepath.Join(t.TempDir(), "notes")
	t.Setenv("HYPERLITE_NOTES_PATH", root)
	var output bytes.Buffer

	command := App{Out: &output}.notepadCommand()
	if err := command.Execute(); err != nil {
		t.Fatal(err)
	}
	if output.Len() != 0 {
		t.Fatalf("empty pinned output = %q", output.String())
	}

	pathCommand := App{Out: &output}.notepadPathCommand()
	if err := pathCommand.Execute(); err != nil {
		t.Fatal(err)
	}
	if output.String() != filepath.Join(root, "pinned.md")+"\n" {
		t.Fatalf("pinned path output = %q", output.String())
	}
	output.Reset()
	pathCommand = App{Out: &output}.notepadPathCommand()
	pathCommand.SetArgs([]string{"--date", "2026-08-02"})
	if err := pathCommand.Execute(); err != nil {
		t.Fatal(err)
	}
	if output.String() != filepath.Join(root, "daily", "2026-08-02.md")+"\n" {
		t.Fatalf("daily path output = %q", output.String())
	}
}

func TestNotepadIndexReturnsPinnedAndDailyDocuments(t *testing.T) {
	root := filepath.Join(t.TempDir(), "notes")
	t.Setenv("HYPERLITE_NOTES_PATH", root)
	store := notepad.Store{}
	if _, err := store.WritePinned("repository paths"); err != nil {
		t.Fatal(err)
	}
	if _, err := store.WriteDaily("2026-08-02", "release notes"); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	command := App{Out: &output}.notepadIndexCommand()
	if err := command.Execute(); err != nil {
		t.Fatal(err)
	}
	var documents []notepad.Document
	if err := json.Unmarshal(output.Bytes(), &documents); err != nil {
		t.Fatal(err)
	}
	if len(documents) != 2 || documents[0].Kind != notepad.KindPinned ||
		documents[1].Date != "2026-08-02" {
		t.Fatalf("index documents = %#v", documents)
	}
}

func TestRootNotepadDoesNotRequireProjectConfiguration(t *testing.T) {
	root := filepath.Join(t.TempDir(), "notes")
	t.Setenv("HYPERLITE_NOTES_PATH", root)
	t.Setenv("HYPERLITE_CONFIG", filepath.Join(t.TempDir(), "invalid.yaml"))
	var output bytes.Buffer

	command := App{Out: &output, Err: &output}.Root()
	command.SetArgs([]string{"notepad", "show", "--date", "2026-08-02"})
	if err := command.Execute(); err != nil {
		t.Fatalf("notepad should be independent of project configuration: %v", err)
	}
}
