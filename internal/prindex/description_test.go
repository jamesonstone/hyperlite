package prindex

import (
	"strings"
	"testing"
)

func TestDescriptionMarkdownKeepsAuthorFormattingAndDropsBotBlocks(t *testing.T) {
	body := "## Description\r\n\r\nFixes the catalog.\r\n\r\n- one\r\n- two\r\n\r\n<!-- template hint -->\r\n\r\n\r\n\r\n" +
		"## Ticket\r\n\r\nCloses #1\r\n\r\n<!-- This is an auto-generated comment: release notes by coderabbit.ai -->\r\n" +
		"## Summary by CodeRabbit\r\n* stuff\r\n<!-- end of auto-generated comment: release notes by coderabbit.ai -->"
	got := descriptionMarkdown(body)
	want := "## Description\n\nFixes the catalog.\n\n- one\n- two\n\n## Ticket\n\nCloses #1"
	if got != want {
		t.Fatalf("got %q\nwant %q", got, want)
	}
}

func TestDescriptionMarkdownTruncatesAtParagraphBoundary(t *testing.T) {
	body := strings.Repeat("a", 900) + "\n\n" + strings.Repeat("b", 900)
	got := descriptionMarkdown(body)
	if !strings.HasSuffix(got, "\n\n…") || strings.Contains(got, "b") {
		t.Fatalf("got %d runes ending %q", len([]rune(got)), got[len(got)-10:])
	}
}
