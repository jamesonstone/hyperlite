package cli

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/threadstate"
)

func TestThreadCommandsRequireExactRevisionAndStdin(t *testing.T) {
	path := filepath.Join(t.TempDir(), "threads.json")
	t.Setenv("HYPERLITE_STATE_PATH", path)
	state := threadstate.Empty()
	state.Threads = []threadstate.ThreadRecord{{
		ID: "issue:owner/repo#7", Aliases: []string{"branch:owner/repo@GH-7"},
		Revision: "revision-1", Moments: []model.AttentionMoment{{
			ID: "moment", Revision: "revision-1", Seen: false, CreatedAt: time.Now(),
		}},
	}}
	if err := (threadstate.Store{}).Write(state); err != nil {
		t.Fatal(err)
	}

	var output bytes.Buffer
	note := App{In: strings.NewReader("coordinate deployment\n"), Out: &output}.threadNoteCommand()
	note.SetArgs([]string{"issue:owner/repo#7"})
	if err := note.Execute(); err == nil || !strings.Contains(err.Error(), "--stdin is required") {
		t.Fatalf("missing --stdin error = %v", err)
	}
	note = App{In: strings.NewReader("coordinate deployment\n"), Out: &output}.threadNoteCommand()
	note.SetArgs([]string{"branch:owner/repo@GH-7", "--stdin"})
	if err := note.Execute(); err != nil {
		t.Fatal(err)
	}

	seen := App{Out: &output}.threadSeenCommand()
	seen.SetArgs([]string{"issue:owner/repo#7", "--revision", "wrong"})
	if err := seen.Execute(); err == nil || !strings.Contains(err.Error(), "advanced") {
		t.Fatalf("wrong revision error = %v", err)
	}
	seen = App{Out: &output}.threadSeenCommand()
	seen.SetArgs([]string{"issue:owner/repo#7", "--revision", "revision-1"})
	if err := seen.Execute(); err != nil {
		t.Fatal(err)
	}
	loaded, _, err := (threadstate.Store{}).Load()
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Threads[0].Note != "coordinate deployment" || !loaded.Threads[0].Moments[0].Seen {
		t.Fatalf("updated state = %#v", loaded.Threads[0])
	}
}
