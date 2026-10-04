package prindex

import (
	"fmt"
	"strings"
)

// githubRepositoryMissing is GitHub's GraphQL message for a repository that
// was deleted, renamed away, or is no longer visible to the caller.
const githubRepositoryMissing = "Could not resolve to a Repository"

// explainedError turns GitHub's missing-repository error into the action the
// operator needs. Projects whose directory is gone never reach here: the CLI
// retires them before scanning.
func explainedError(message, repository, path string) string {
	if !strings.Contains(message, githubRepositoryMissing) {
		return message
	}
	return fmt.Sprintf(
		"GitHub repository %s no longer exists (deleted, renamed, or access removed). "+
			"Delete the local directory %s, or remove it with `hyperlite projects remove %s`.",
		repository, path, path,
	)
}
