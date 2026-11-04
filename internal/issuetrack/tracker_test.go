package issuetrack

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

const labcoreKit = `
issues:
    provider: linear
    linear:
        workspace: lsmc
        team_id: add0a7c5-383d-4969-98d4-a5402b4cac66
`

func TestLoadSelectsLinearGitHubAndSilentFallback(t *testing.T) {
	for _, tc := range []struct {
		name      string
		body      string
		provider  string
		workspace string
		skipWrite bool
		asDir     bool
	}{
		{name: "missing file", provider: ProviderGitHub, skipWrite: true},
		{name: "empty file", body: "", provider: ProviderGitHub},
		{name: "no issues block", body: "schema_version: 2\n", provider: ProviderGitHub},
		{name: "provider omitted", body: "issues: {}\n", provider: ProviderGitHub},
		{name: "provider github", body: "issues:\n    provider: github\n", provider: ProviderGitHub},
		{
			name:     "github keeps a leftover linear block",
			body:     "issues:\n    provider: github\n    linear:\n        workspace: lsmc\n        team_id: add0a7c5-383d-4969-98d4-a5402b4cac66\n",
			provider: ProviderGitHub,
		},
		{name: "labcore linear", body: labcoreKit, provider: ProviderLinear, workspace: "lsmc"},
		{
			name:      "linear without project id",
			body:      "issues:\n  provider: Linear\n  linear:\n    workspace: lsmc\n    team_id: add0a7c5-383d-4969-98d4-a5402b4cac66\n    project_id:\n",
			provider:  ProviderLinear,
			workspace: "lsmc",
		},
		{
			name:     "linear with project id",
			body:     "issues:\n    provider: linear\n    linear:\n        workspace: lsmc\n        team_id: ADD0A7C5-383D-4969-98D4-A5402B4CAC66\n        project_id: 22222222-2222-4222-8222-222222222222\n",
			provider: ProviderLinear, workspace: "lsmc",
		},
		{name: "linear missing team", body: "issues:\n    provider: linear\n    linear:\n        workspace: lsmc\n", provider: ProviderGitHub},
		{name: "workspace is a url", body: "issues:\n    provider: linear\n    linear:\n        workspace: https://linear.app/lsmc\n        team_id: add0a7c5-383d-4969-98d4-a5402b4cac66\n", provider: ProviderGitHub},
		{name: "unknown provider", body: "issues:\n    provider: linera\n", provider: ProviderGitHub},
		{name: "invalid yaml", body: "issues: [\n", provider: ProviderGitHub},
		{name: "kit path is a directory", provider: ProviderGitHub, asDir: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			path := filepath.Join(root, ".kit.yaml")
			switch {
			case tc.skipWrite:
			case tc.asDir:
				if err := os.Mkdir(path, 0o755); err != nil {
					t.Fatal(err)
				}
			default:
				if err := os.WriteFile(path, []byte(tc.body), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			got := Load(root)
			if got.Provider != tc.provider || got.Workspace != tc.workspace {
				t.Fatalf("Load() = %#v, want provider %s workspace %q", got, tc.provider, tc.workspace)
			}
		})
	}
}

func TestLoadTreatsAnUnreadableFileAsGitHub(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Log("running as root, mode 000 is still readable; directory and parse fallbacks cover this case")
		return
	}
	root := t.TempDir()
	path := filepath.Join(root, ".kit.yaml")
	if err := os.WriteFile(path, []byte(labcoreKit), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(path, 0o644) })
	if got := Load(root); got.Provider != ProviderGitHub || got.Workspace != "" {
		t.Fatalf("unreadable config = %#v", got)
	}
}

func TestLoadSkipsOversizedConfig(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, ".kit.yaml")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := file.Truncate(maxKitConfigBytes + 1); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	reads := 0
	orig := readKitFile
	readKitFile = func(name string) ([]byte, error) {
		reads++
		return orig(name)
	}
	t.Cleanup(func() { readKitFile = orig })
	if got := Load(root); got.Provider != ProviderGitHub || reads != 0 {
		t.Fatalf("provider %#v reads %d", got, reads)
	}
}

func TestLoadCachesUntilSizeOrMtimeChanges(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, ".kit.yaml")
	if err := os.WriteFile(path, []byte(labcoreKit), 0o644); err != nil {
		t.Fatal(err)
	}
	reads := 0
	orig := readKitFile
	readKitFile = func(name string) ([]byte, error) {
		reads++
		return orig(name)
	}
	t.Cleanup(func() { readKitFile = orig })

	if got := Load(root); got.Provider != ProviderLinear || got.Workspace != "lsmc" || reads != 1 {
		t.Fatalf("first %#v reads %d", got, reads)
	}
	if got := Load(root); got.Provider != ProviderLinear || reads != 1 {
		t.Fatalf("cached %#v reads %d", got, reads)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("issues:\n    provider: github\n"), info.Mode()); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, info.ModTime(), info.ModTime()); err != nil {
		t.Fatal(err)
	}
	if got := Load(root); got.Provider != ProviderGitHub || reads != 2 {
		t.Fatalf("size change %#v reads %d", got, reads)
	}
	updated := info.ModTime().Add(2 * time.Second)
	if err := os.Chtimes(path, updated, updated); err != nil {
		t.Fatal(err)
	}
	// Same bytes and a new mtime still re-reads, then caches the github result.
	if got := Load(root); got.Provider != ProviderGitHub || reads != 3 {
		t.Fatalf("mtime change %#v reads %d", got, reads)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if got := Load(root); got.Provider != ProviderGitHub {
		t.Fatalf("deleted config = %#v", got)
	}
}

func TestLinkLinearAndGitHub(t *testing.T) {
	linear := Tracker{Provider: ProviderLinear, Workspace: "lsmc"}
	github := Tracker{Provider: ProviderGitHub}
	for _, tc := range []struct {
		name, provider      string
		tracker             Tracker
		branch, title, repo string
		label, link         string
	}{
		{
			name: "linear branch", tracker: linear, branch: "ENG-67-admit-orders", title: "feat: other",
			label: "ENG-67", link: "https://linear.app/lsmc/issue/ENG-67",
		},
		{
			name: "linear key later in the branch", tracker: linear, branch: "topic-ENG-67-notes", title: "other",
			label: "ENG-67", link: "https://linear.app/lsmc/issue/ENG-67",
		},
		{
			name: "linear lowercase branch", tracker: linear, branch: "feature/eng-67-admit",
			title: "unrelated", label: "ENG-67", link: "https://linear.app/lsmc/issue/ENG-67",
		},
		{
			name: "linear scope beats a later technical token", tracker: linear, branch: "feature/x",
			title: "fix(ENG-67): parse UTF-8 and SHA-256", label: "ENG-67",
			link: "https://linear.app/lsmc/issue/ENG-67",
		},
		{
			name: "linear title token", tracker: linear, branch: "feature/x", title: "admit ENG-67 orders",
			label: "ENG-67", link: "https://linear.app/lsmc/issue/ENG-67",
		},
		{
			name: "linear prefers branch over title", tracker: linear, branch: "ENG-10-cleanup",
			title: "fix(ENG-67): nope", label: "ENG-10", link: "https://linear.app/lsmc/issue/ENG-10",
		},
		{
			name: "linear skips a GH branch and uses the title", tracker: linear, branch: "GH-1265",
			title: "fix(ENG-67): admit buccal partner orders", label: "ENG-67",
			link: "https://linear.app/lsmc/issue/ENG-67",
		},
		{
			name: "linear ignores technical tokens", tracker: linear, branch: "utf-8-parser",
			title: "parse UTF-8 and SHA-256",
		},
		{
			name: "linear without a ticket", tracker: linear, branch: "feature/x", title: "build(deps): bump x",
		},
		{
			name: "linear ignores a module version", tracker: linear,
			branch: "dependabot/go_modules/golang.org/x/sys-0.48.0",
			title:  "build(deps): bump golang.org/x/sys from 0.47.0 to 0.48.0",
		},
		{
			name: "github branch", tracker: github, branch: "GH-538", title: "feat: rename field",
			repo: "lsmc-bio/labcore-ui", label: "GH-538",
			link: "https://github.com/lsmc-bio/labcore-ui/issues/538",
		},
		{
			name: "github title fallback", tracker: github, branch: "feature/x", title: "feat(GH-96): show workflows",
			repo: "o/r", label: "GH-96", link: "https://github.com/o/r/issues/96",
		},
		{name: "github inside a word", tracker: github, branch: "high-5", title: "cough-9 tough-2"},
		{name: "github lowercase", tracker: github, branch: "gh-12"},
		{name: "github incomplete token", tracker: github, branch: "GH-12foo", title: "GH-34bar"},
		{
			name: "github separator completes the token", tracker: github, branch: "GH-12-cleanup",
			repo: "o/r", label: "GH-12", link: "https://github.com/o/r/issues/12",
		},
		{
			name: "github label without a repository slug", tracker: github, branch: "GH-7", repo: "labcore",
			label: "GH-7",
		},
		{
			name: "linear title does not link on a github repo", tracker: github, branch: "feature/x",
			title: "fix(ENG-67): admit", repo: "lsmc-bio/labcore",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			label, link := tc.tracker.Link(tc.branch, tc.title, tc.repo)
			if label != tc.label || link != tc.link {
				t.Fatalf("Link() = %q %q, want %q %q", label, link, tc.label, tc.link)
			}
		})
	}
}

func ExampleTracker_Link() {
	tracker := Tracker{Provider: ProviderLinear, Workspace: "lsmc"}
	label, link := tracker.Link("ENG-67", "fix(ENG-67): admit buccal partner orders", "lsmc-bio/labcore")
	fmt.Println(label)
	fmt.Println(link)
	// Output:
	// ENG-67
	// https://linear.app/lsmc/issue/ENG-67
}
