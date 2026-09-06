package prindex

import (
	"strings"
	"testing"
)

func TestGlanceSummaryPrefersOriginalAsk(t *testing.T) {
	body := "Original ask: keep hover from opening GitHub.\n\n" +
		"Implementation summary: expand the batched query."
	got := glanceSummary("feat(GH-72): :sparkles: add hover why", body, nil)
	if got != "keep hover from opening GitHub." {
		t.Fatalf("summary = %q", got)
	}
}

func TestGlanceSummarySkipsTitleAndTemplateThenUsesBody(t *testing.T) {
	body := "## Summary\n\n" +
		"feat(GH-72): :sparkles: add hover why\n\n" +
		"How to Test\n\n" +
		"- [ ] hover a row\n\n" +
		"Closes #72\n\n" +
		"Bridge software fixture custody without a second GitHub round trip."
	got := glanceSummary("feat(GH-72): :sparkles: add hover why", body, []string{
		"feat(GH-72): :sparkles: add hover why",
	})
	if got != "Bridge software fixture custody without a second GitHub round trip." {
		t.Fatalf("summary = %q", got)
	}
}

func TestGlanceSummaryFallsBackToDistinctCommitHeadlines(t *testing.T) {
	got := glanceSummary(
		"feat(GH-72): :sparkles: add hover why",
		"",
		[]string{"wip wiring", "feat(GH-72): :sparkles: add hover why", "explain hover intent"},
	)
	if got != "explain hover intent · wip wiring" {
		t.Fatalf("summary = %q", got)
	}
}

func TestGlanceSummaryOmitsTitleOnlyEvidence(t *testing.T) {
	got := glanceSummary(
		"Ship hover",
		"Ship hover\n\nCloses #12",
		[]string{"Ship hover", "Merge branch 'main'"},
	)
	if got != "" {
		t.Fatalf("summary = %q", got)
	}
}

func TestTruncateRunesKeepsWordBoundary(t *testing.T) {
	long := strings.Repeat("word ", 80)
	got := truncateRunes(long, 40)
	if got == long || !strings.HasSuffix(got, "…") {
		t.Fatalf("truncated = %q", got)
	}
}
