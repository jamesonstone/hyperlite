package prindex

import (
	"strings"
	"testing"
)

func TestGlanceSummaryJoinsParagraphsUpToTheLimit(t *testing.T) {
	body := "First paragraph explains the change.\n\nSecond adds context.\n\n" + strings.Repeat("x", 700)
	summary := glanceSummary("title", body, nil)
	if !strings.HasPrefix(summary, "First paragraph explains the change. Second adds context.") {
		t.Fatalf("summary = %q", summary)
	}
	if runes := len([]rune(summary)); runes > glanceSummaryLimit+1 {
		t.Fatalf("summary has %d runes, limit %d", runes, glanceSummaryLimit)
	}
}
