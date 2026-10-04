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
// summary), cut at a paragraph boundary outside fenced code when long.
// Whitespace cleanup applies only outside fenced code so code renders exactly
// as written.
func descriptionMarkdown(body string) string {
	text := strings.ReplaceAll(body, "\r\n", "\n")
	text = generatedBlock.ReplaceAllString(text, "")
	text = htmlComment.ReplaceAllString(text, "")
	text = strings.TrimSpace(tidyProse(text))
	if utf8.RuneCountInString(text) <= descriptionLimit {
		return text
	}
	return truncateDescription(text) + "\n\n…"
}

// truncateDescription keeps whole lines up to the limit, preferring the last
// blank line outside fenced code; a cut inside a fence closes it.
func truncateDescription(text string) string {
	lines := strings.Split(text, "\n")
	fence, runes := "", 0
	kept, boundary := 0, -1
	partial := ""
	for index, line := range lines {
		length := utf8.RuneCountInString(line) + 1
		if runes+length > descriptionLimit {
			// A prose line crossing the limit is cut mid-line to use the budget.
			if fence == "" {
				partial = string([]rune(line)[:max(0, descriptionLimit-runes)])
			}
			break
		}
		runes += length
		fence = nextFence(fence, strings.TrimSpace(line))
		kept = index + 1
		if fence == "" && strings.TrimSpace(line) == "" && runes > descriptionLimit/3 {
			boundary = index
		}
	}
	if boundary >= 0 {
		return strings.TrimSpace(strings.Join(lines[:boundary], "\n"))
	}
	cut := strings.TrimSpace(strings.Join(append(append([]string{}, lines[:kept]...), partial), "\n"))
	if fence != "" {
		cut += "\n" + fence
	}
	return cut
}

// tidyProse trims trailing whitespace and collapses runs of blank lines,
// leaving fenced code blocks untouched.
func tidyProse(text string) string {
	var out []string
	fence := ""
	blanks := 0
	for _, line := range strings.Split(text, "\n") {
		trimmed := strings.TrimSpace(line)
		next := nextFence(fence, trimmed)
		if next != fence || (fence != "" && next == "") {
			fence = next
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

// nextFence returns the open fence after a line: an opener may carry an info
// string, but a closer is only a run of the opening character at least as long
// as the opener, followed by nothing but whitespace.
func nextFence(open, trimmed string) string {
	marker := fenceMarker(trimmed)
	if open == "" {
		return marker
	}
	if marker != "" && marker[0] == open[0] && len(marker) >= len(open) && trimmed == marker {
		return ""
	}
	return open
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
