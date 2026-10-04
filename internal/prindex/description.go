package prindex

import (
	"regexp"
	"strings"
	"unicode/utf8"
)

// descriptionLimit bounds the Markdown kept per pull request for the hover
// card, so the cache and scan stay small with many open pull requests.
const descriptionLimit = 1500

var (
	generatedBlock = regexp.MustCompile(`(?s)<!--\s*This is an auto-generated comment.*?<!--\s*end of auto-generated comment[^>]*-->`)
	htmlComment    = regexp.MustCompile(`(?s)<!--.*?-->`)
)

// descriptionMarkdown returns the pull request body as the author wrote it,
// minus HTML comments and bot-generated blocks (such as CodeRabbit's
// summary), cut at a paragraph boundary when long. Whitespace cleanup applies
// only outside fenced code so code renders exactly as written.
func descriptionMarkdown(body string) string {
	text := strings.ReplaceAll(body, "\r\n", "\n")
	text = generatedBlock.ReplaceAllString(text, "")
	text = htmlComment.ReplaceAllString(text, "")
	text = strings.TrimSpace(tidyProse(text))
	if utf8.RuneCountInString(text) <= descriptionLimit {
		return text
	}
	cut := string([]rune(text)[:descriptionLimit])
	if boundary := strings.LastIndex(cut, "\n\n"); boundary >= 0 &&
		utf8.RuneCountInString(cut[:boundary]) > descriptionLimit/3 {
		cut = cut[:boundary]
	}
	return strings.TrimSpace(cut) + "\n\n…"
}

// tidyProse trims trailing whitespace and collapses runs of blank lines,
// leaving fenced code blocks untouched.
func tidyProse(text string) string {
	var out []string
	fence := ""
	blanks := 0
	for _, line := range strings.Split(text, "\n") {
		trimmed := strings.TrimSpace(line)
		if marker := fenceMarker(trimmed); marker != "" && (fence == "" || strings.HasPrefix(marker, fence)) {
			if fence == "" {
				fence = marker
			} else {
				fence = ""
			}
			blanks = 0
			out = append(out, strings.TrimRight(line, " \t"))
			continue
		}
		if fence != "" {
			out = append(out, line)
			continue
		}
		line = strings.TrimRight(line, " \t")
		if line == "" {
			blanks++
			if blanks > 1 {
				continue
			}
		} else {
			blanks = 0
		}
		out = append(out, line)
	}
	return strings.Join(out, "\n")
}

// fenceMarker returns the opening run of a ``` or ~~~ fence line.
func fenceMarker(line string) string {
	for _, char := range []string{"`", "~"} {
		run := len(line) - len(strings.TrimLeft(line, char))
		if run >= 3 {
			return strings.Repeat(char, run)
		}
	}
	return ""
}
