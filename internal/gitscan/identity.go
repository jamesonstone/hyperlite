package gitscan

import (
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

var issueBranchPattern = regexp.MustCompile(`(?i)^GH-(\d+)$`)

func IssueNumber(branch string) int {
	match := issueBranchPattern.FindStringSubmatch(strings.TrimSpace(branch))
	if len(match) != 2 {
		return 0
	}
	number, err := strconv.Atoi(match[1])
	if err != nil || number <= 0 {
		return 0
	}
	return number
}

func IdentityBranch(local LocalLane) string {
	if local.Worktree.Detached {
		name := filepath.Base(filepath.Clean(local.Worktree.Path))
		if IssueNumber(name) > 0 {
			return name
		}
	}
	return local.Branch
}
