package prindex

import (
	"strings"
	"unicode"
)

const glanceSummaryLimit = 160

func glanceSummary(title, body string, headlines []string) string {
	if text := firstUsefulBody(body, title); text != "" {
		return truncateRunes(text, glanceSummaryLimit)
	}
	return truncateRunes(commitFallback(title, headlines), glanceSummaryLimit)
}

func firstUsefulBody(body, title string) string {
	normalized := strings.ReplaceAll(body, "\r\n", "\n")
	normalized = strings.ReplaceAll(normalized, "\r", "\n")
	if ask := labeledParagraph(normalized, "original ask:"); ask != "" && !repeatsTitle(ask, title) {
		return ask
	}
	for _, paragraph := range strings.Split(normalized, "\n\n") {
		text := collapseSpace(stripMarkdownPrefix(paragraph))
		if text == "" || isMetaParagraph(text) || repeatsTitle(text, title) {
			continue
		}
		return text
	}
	return ""
}

func labeledParagraph(body, label string) string {
	for _, paragraph := range strings.Split(body, "\n\n") {
		text := collapseSpace(stripMarkdownPrefix(paragraph))
		lower := strings.ToLower(text)
		if !strings.HasPrefix(lower, label) {
			continue
		}
		rest := collapseSpace(text[len(label):])
		if rest != "" {
			return rest
		}
	}
	return ""
}

func commitFallback(title string, headlines []string) string {
	seen := map[string]struct{}{}
	var parts []string
	for index := len(headlines) - 1; index >= 0; index-- {
		headline := collapseSpace(headlines[index])
		if headline == "" || isMergeHeadline(headline) || repeatsTitle(headline, title) {
			continue
		}
		key := strings.ToLower(headline)
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		parts = append(parts, headline)
	}
	return strings.Join(parts, " · ")
}

func commitHeadlines(commits *rawCommitConnection) []string {
	if commits == nil {
		return nil
	}
	headlines := make([]string, 0, len(commits.Nodes))
	for _, node := range commits.Nodes {
		if headline := strings.TrimSpace(node.Commit.MessageHeadline); headline != "" {
			headlines = append(headlines, headline)
		}
	}
	return headlines
}

func isMetaParagraph(text string) bool {
	lower := strings.ToLower(text)
	if isIssueTrailer(lower) {
		return true
	}
	switch lower {
	case "summary", "description", "context", "purpose",
		"how to test", "test plan", "ticket":
		return true
	}
	if strings.Contains(lower, "auto-generated comment") {
		return true
	}
	if strings.HasPrefix(lower, "- [") || strings.HasPrefix(lower, "* [") {
		return true
	}
	return false
}

func isIssueTrailer(lower string) bool {
	prefixes := []string{"closes #", "fixes #", "resolves #", "refs #"}
	for _, prefix := range prefixes {
		if strings.HasPrefix(lower, prefix) {
			return true
		}
	}
	return false
}

func isMergeHeadline(text string) bool {
	lower := strings.ToLower(text)
	return strings.HasPrefix(lower, "merge ") || strings.HasPrefix(lower, "merge:")
}

func repeatsTitle(text, title string) bool {
	left := comparableMessage(text)
	right := comparableMessage(title)
	if left == "" || right == "" {
		return false
	}
	return left == right
}

func comparableMessage(text string) string {
	value := strings.ToLower(collapseSpace(text))
	if index := strings.Index(value, ": "); index >= 0 && index < 48 {
		value = strings.TrimSpace(value[index+2:])
	}
	value = strings.TrimLeftFunc(value, func(r rune) bool {
		return r == ':' || unicode.IsSpace(r)
	})
	return value
}

func stripMarkdownPrefix(paragraph string) string {
	var lines []string
	for _, line := range strings.Split(paragraph, "\n") {
		trimmed := strings.TrimSpace(line)
		trimmed = strings.ReplaceAll(trimmed, "**", "")
		trimmed = strings.ReplaceAll(trimmed, "__", "")
		trimmed = strings.TrimLeft(trimmed, "#>`")
		trimmed = strings.TrimSpace(trimmed)
		if trimmed != "" {
			lines = append(lines, trimmed)
		}
	}
	return strings.Join(lines, " ")
}

func collapseSpace(text string) string {
	return strings.Join(strings.Fields(text), " ")
}

func truncateRunes(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	cut := limit
	for cut > 0 && !unicode.IsSpace(runes[cut-1]) {
		cut--
	}
	if cut < limit/2 {
		cut = limit
	}
	return strings.TrimSpace(string(runes[:cut])) + "…"
}
