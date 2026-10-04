package prindex

import (
	"strings"
	"testing"
)

func TestExplainedErrorNamesRepositoryAndDirectory(t *testing.T) {
	message := explainedError(
		"gh: Could not resolve to a Repository with the name 'owner/gone'.", "owner/gone", "/src/gone",
	)
	if !strings.Contains(message, "owner/gone no longer exists") || !strings.Contains(message, "/src/gone") {
		t.Fatalf("message = %q", message)
	}
	if explainedError("gh: HTTP 502", "owner/one", "/src/one") != "gh: HTTP 502" {
		t.Fatal("other errors must pass through unchanged")
	}
}
