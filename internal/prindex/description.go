package prindex

import (
	"regexp"
	"strings"
)

// descriptionLimit bounds the Markdown kept per pull request for the hover
// card, so the cache and scan stay small with many open pull requests.
const descriptionLimit = 1500

var (
	generatedBlock = regexp.MustCompile(`(?s)<!--\s*This is an auto-generated comment.*?<!--\s*end of auto-generated comment[^>]*-->`)
	htmlComment    = regexp.MustCompile(`(?s)<!--.*?-->`)
	extraBlankRuns = regexp.MustCompile(`\n{3,}`)
)

// descriptionMarkdown returns the pull request body as the author wrote it,
// minus HTML comments and bot-generated blocks (such as CodeRabbit's
// summary), cut at a paragraph boundary when long.
func descriptionMarkdown(body string) string {
	text := strings.ReplaceAll(body, "\r\n", "\n")
	text = generatedBlock.ReplaceAllString(text, "")
	text = htmlComment.ReplaceAllString(text, "")
	lines := strings.Split(text, "\n")
	for index, line := range lines {
		lines[index] = strings.TrimRight(line, " \t")
	}
	text = extraBlankRuns.ReplaceAllString(strings.Join(lines, "\n"), "\n\n")
	text = strings.TrimSpace(text)
	runes := []rune(text)
	if len(runes) <= descriptionLimit {
		return text
	}
	cut := string(runes[:descriptionLimit])
	if boundary := strings.LastIndex(cut, "\n\n"); boundary > descriptionLimit/3 {
		cut = cut[:boundary]
	}
	return strings.TrimSpace(cut) + "\n\n…"
}
