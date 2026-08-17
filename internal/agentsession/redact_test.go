package agentsession

import (
	"strings"
	"testing"
)

func TestRedactSignedURLsPreservesWhitespace(t *testing.T) {
	plain := "first\t  second\nhttps://example.test/path?safe=yes"
	if got := redactSignedURLs(plain); got != plain {
		t.Fatalf("plain text layout changed: %q", got)
	}
	value := "first\t  second\n(https://example.test/path?safe=yes&X-Amz-Signature=hidden), end"
	got := redactSignedURLs(value)
	if !strings.Contains(got, "first\t  second\n(") || !strings.Contains(got, "), end") {
		t.Fatalf("redaction changed whitespace or punctuation: %q", got)
	}
	if strings.Contains(got, "hidden") || !strings.Contains(got, "X-Amz-Signature=REDACTED") {
		t.Fatalf("signed URL was not redacted: %q", got)
	}
}

func TestRedactSignedURLInsideMarkdownAutolink(t *testing.T) {
	value := "before\t<https://example.test/path?safe=yes&X-Amz-Signature=hidden>\nafter"
	got := redactSignedURLs(value)
	if !strings.HasPrefix(got, "before\t<https://") || !strings.HasSuffix(got, ">\nafter") {
		t.Fatalf("autolink wrappers or layout changed: %q", got)
	}
	if strings.Contains(got, "hidden") || !strings.Contains(got, "X-Amz-Signature=REDACTED") {
		t.Fatalf("autolink signature was not redacted: %q", got)
	}
}
