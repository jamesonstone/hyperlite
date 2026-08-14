package cli

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/pinboard"
)

func TestPinboardCommandsAreConfigurationIndependent(t *testing.T) {
	root := filepath.Join(t.TempDir(), "board")
	t.Setenv("HYPERLITE_PINBOARD_PATH", root)
	t.Setenv("HYPERLITE_CONFIG", filepath.Join(t.TempDir(), "missing.yaml"))

	var output strings.Builder
	mutation := `{"kind":"add_section","title":"Ideas"}`
	command := App{In: strings.NewReader(mutation), Out: &output}.Root()
	command.SetArgs([]string{"pinboard", "mutate", "--stdin"})
	if err := command.Execute(); err != nil {
		t.Fatal(err)
	}
	var created pinboard.Snapshot
	if err := json.Unmarshal([]byte(output.String()), &created); err != nil {
		t.Fatal(err)
	}
	if len(created.Board.Sections) != 1 || created.Board.Sections[0].Title != "Ideas" {
		t.Fatalf("created snapshot = %#v", created)
	}

	output.Reset()
	show := App{Out: &output}.Root()
	show.SetArgs([]string{"pinboard", "show"})
	if err := show.Execute(); err != nil {
		t.Fatal(err)
	}
	var loaded pinboard.Snapshot
	if err := json.Unmarshal([]byte(output.String()), &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.Board.Sections[0].ID != created.Board.Sections[0].ID {
		t.Fatalf("loaded snapshot = %#v", loaded)
	}
}

func TestPinboardMutationRejectsMissingFlagUnknownFieldsAndTrailingValues(t *testing.T) {
	t.Setenv("HYPERLITE_PINBOARD_PATH", filepath.Join(t.TempDir(), "board"))
	tests := map[string]struct {
		input string
		args  []string
	}{
		"missing stdin flag": {`{"kind":"add_section","title":"Ideas"}`, []string{"pinboard", "mutate"}},
		"unknown field":      {`{"kind":"add_section","title":"Ideas","extra":true}`, []string{"pinboard", "mutate", "--stdin"}},
		"trailing value":     {`{"kind":"add_section","title":"Ideas"} {}`, []string{"pinboard", "mutate", "--stdin"}},
	}
	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			command := App{In: strings.NewReader(test.input), Out: &strings.Builder{}}.Root()
			command.SetArgs(test.args)
			if err := command.Execute(); err == nil {
				t.Fatal("expected mutation error")
			}
		})
	}
}
