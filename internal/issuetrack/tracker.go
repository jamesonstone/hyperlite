// Package issuetrack reads a checkout's Kit issue provider and builds the
// issue link Hyperlite shows for a pull request.
package issuetrack

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"go.yaml.in/yaml/v3"
)

const (
	ProviderGitHub = "github"
	ProviderLinear = "linear"

	kitFile           = ".kit.yaml"
	maxKitConfigBytes = 1 << 20
)

// Tracker is the issue provider for one checkout. The zero value and
// ProviderGitHub both link GH-<n> to GitHub.
type Tracker struct {
	Provider  string
	Workspace string
}

type kitDocument struct {
	Issues *issueConfig `yaml:"issues"`
}

type issueConfig struct {
	Provider string       `yaml:"provider"`
	Linear   linearConfig `yaml:"linear"`
}

type linearConfig struct {
	Workspace string `yaml:"workspace"`
	TeamID    string `yaml:"team_id"`
	ProjectID string `yaml:"project_id"`
}

type cachedKit struct {
	modTime time.Time
	size    int64
	tracker Tracker
}

var (
	cacheMu     sync.Mutex
	parsedKits  = map[string]cachedKit{}
	readKitFile = os.ReadFile

	// Kit accepts a workspace URL slug and UUID team (and optional project) ids.
	linearWorkspacePattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]*$`)
	linearIDPattern        = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

	githubToken = regexp.MustCompile(`\bGH-([0-9]+)\b`)
	// A Linear key is a 2-7 character team key, starting with a letter, then a number.
	linearToken = regexp.MustCompile(`(?i)(?:^|[^\p{L}\p{N}_])([a-z][a-z0-9]{1,6}-[0-9]+)\b`)
	scopeToken  = regexp.MustCompile(`(?i)^[a-z]+!?\(([a-z][a-z0-9]{1,6}-[0-9]+)\)`)
)

// Load reads root/.kit.yaml. Any failure, including a missing file, selects
// GitHub and returns no error.
func Load(root string) Tracker {
	github := Tracker{Provider: ProviderGitHub}
	if strings.TrimSpace(root) == "" {
		return github
	}
	path := filepath.Join(filepath.Clean(root), kitFile)
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() || info.Size() == 0 || info.Size() > maxKitConfigBytes {
		return github
	}
	if tracker, ok := lookup(path, info); ok {
		return tracker
	}
	data, err := readKitFile(path)
	if err != nil {
		return github
	}
	tracker := parseKit(data)
	store(path, info, tracker)
	return tracker
}

func lookup(path string, info os.FileInfo) (Tracker, bool) {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	hit, ok := parsedKits[path]
	if !ok || !hit.modTime.Equal(info.ModTime()) || hit.size != info.Size() {
		return Tracker{}, false
	}
	return hit.tracker, true
}

func store(path string, info os.FileInfo, tracker Tracker) {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	parsedKits[path] = cachedKit{modTime: info.ModTime(), size: info.Size(), tracker: tracker}
}

func parseKit(data []byte) Tracker {
	github := Tracker{Provider: ProviderGitHub}
	var doc kitDocument
	if err := yaml.Unmarshal(data, &doc); err != nil || doc.Issues == nil || !doc.Issues.linearReady() {
		return github
	}
	return Tracker{
		Provider:  ProviderLinear,
		Workspace: strings.TrimSpace(doc.Issues.Linear.Workspace),
	}
}

func (c issueConfig) linearReady() bool {
	if !strings.EqualFold(strings.TrimSpace(c.Provider), ProviderLinear) {
		return false
	}
	if !linearWorkspacePattern.MatchString(strings.TrimSpace(c.Linear.Workspace)) {
		return false
	}
	if !linearIDPattern.MatchString(strings.TrimSpace(c.Linear.TeamID)) {
		return false
	}
	project := strings.TrimSpace(c.Linear.ProjectID)
	return project == "" || linearIDPattern.MatchString(project)
}

// Link returns the label and URL for the ticket named by branch or title.
// An empty label means the pull request names no ticket for this provider.
func (t Tracker) Link(branch, title, repository string) (label, link string) {
	if t.Provider == ProviderLinear {
		key := linearKey(branch, title)
		if key == "" || t.Workspace == "" {
			return "", ""
		}
		return key, fmt.Sprintf("https://linear.app/%s/issue/%s", t.Workspace, key)
	}
	number, ok := githubNumber(branch, title)
	if !ok {
		return "", ""
	}
	label = fmt.Sprintf("GH-%d", number)
	if strings.Contains(repository, "/") {
		link = fmt.Sprintf("https://github.com/%s/issues/%d", repository, number)
	}
	return label, link
}

func githubNumber(branch, title string) (int, bool) {
	if number, ok := githubIssue(branch); ok {
		return number, true
	}
	return githubIssue(title)
}

func githubIssue(text string) (int, bool) {
	match := githubToken.FindStringSubmatch(text)
	if match == nil {
		return 0, false
	}
	number, err := strconv.Atoi(match[1])
	if err != nil {
		return 0, false
	}
	return number, true
}

func linearKey(branch, title string) string {
	if key := firstKey(linearToken, branch); key != "" {
		return key
	}
	if key := firstKey(scopeToken, title); key != "" {
		return key
	}
	return firstKey(linearToken, title)
}

func firstKey(pattern *regexp.Regexp, text string) string {
	for _, loc := range pattern.FindAllStringSubmatchIndex(text, -1) {
		if len(loc) < 4 || loc[2] < 0 || loc[3] < 0 || dottedVersion(text, loc[3]) {
			continue
		}
		if key := acceptKey(text[loc[2]:loc[3]]); key != "" {
			return key
		}
	}
	return ""
}

// dottedVersion reports a token that continues as a dotted numeric version,
// such as sys-0.48.0 or lodash-4.17.21. end is the index just after the token.
func dottedVersion(text string, end int) bool {
	if end < 0 || end+1 >= len(text) || text[end] != '.' {
		return false
	}
	next := text[end+1]
	return next >= '0' && next <= '9'
}

func acceptKey(raw string) string {
	key := strings.ToUpper(strings.TrimSpace(raw))
	team, _, ok := strings.Cut(key, "-")
	if !ok || rejectedTeam(team) {
		return ""
	}
	return key
}

// rejectedTeam drops tokens that collide with the GitHub convention or with
// ordinary technical identifiers. A team that picked one of these keys would
// not get a Linear link.
func rejectedTeam(team string) bool {
	switch team {
	case "GH", "PR", "UTF", "ISO", "RFC", "CVE", "SHA", "HTTP", "HTTPS", "ASCII", "AES", "RSA", "TLS", "SSL":
		return true
	default:
		return false
	}
}
