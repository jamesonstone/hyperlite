package memoryscan

import (
	"errors"
	"regexp"
	"strings"
)

var (
	listItemPrefix  = regexp.MustCompile(`^(?:[-*]\s+|\d+[.)]\s+)`)
	obligationWord  = regexp.MustCompile(`(?i)\b(deploy|deployment|infrastructure|migration|production|provision|activate|rollout|postgres|s3|cloudformation|ecs|certificate|secret|runbook)\b`)
	implicationWord = regexp.MustCompile(`(?i)\b(public|security|breaking|authority|ownership|owns|must|production|infrastructure|migration|external|operational)\b`)
)

func splitFrontmatter(contents []byte) ([]byte, []byte, error) {
	text := string(contents)
	if !strings.HasPrefix(text, "---\n") {
		return nil, contents, nil
	}
	end := strings.Index(text[4:], "\n---")
	if end < 0 {
		return nil, nil, errors.New("unterminated front matter")
	}
	end += 4
	bodyStart := end + len("\n---")
	for bodyStart < len(text) && (text[bodyStart] == '\r' || text[bodyStart] == '\n') {
		bodyStart++
	}
	return []byte(text[4:end]), []byte(text[bodyStart:]), nil
}

func markdownSections(contents []byte) (map[string]string, string) {
	sections := make(map[string]string)
	var title, current string
	var lines []string
	flush := func() {
		if current == "" {
			return
		}
		value := strings.TrimSpace(strings.Join(lines, "\n"))
		if len(value) > maxSectionBytes {
			value = value[:maxSectionBytes]
		}
		sections[current] = value
	}
	for _, line := range strings.Split(string(contents), "\n") {
		if strings.HasPrefix(line, "# ") && title == "" {
			title = strings.TrimSpace(strings.TrimPrefix(line, "# "))
			continue
		}
		if strings.HasPrefix(line, "## ") {
			flush()
			current = strings.ToUpper(strings.TrimSpace(strings.TrimPrefix(line, "## ")))
			lines = nil
			continue
		}
		if current != "" {
			lines = append(lines, line)
		}
	}
	flush()
	return sections, title
}

func section(sections map[string]string, names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(sections[name]); value != "" {
			return value
		}
	}
	return ""
}

func joinSections(sections map[string]string, names ...string) string {
	var values []string
	for _, name := range names {
		if value := strings.TrimSpace(sections[name]); value != "" {
			values = append(values, value)
		}
	}
	return strings.Join(values, "\n\n")
}

func candidates(value string, pattern *regexp.Regexp, category string) []Candidate {
	var result []Candidate
	seen := make(map[string]struct{})
	for _, line := range candidateStatements(value) {
		line = strings.TrimSpace(line)
		if line == "" || !pattern.MatchString(line) {
			continue
		}
		lower := strings.ToLower(line)
		if strings.HasPrefix(lower, "no ") || strings.Contains(lower, " no ") ||
			strings.Contains(lower, "not required") || strings.Contains(lower, "without ") {
			continue
		}
		satisfied := strings.Contains(line, "[x]") || strings.Contains(strings.ToLower(line), "completed")
		line = strings.ReplaceAll(strings.ReplaceAll(line, "[ ]", ""), "[x]", "")
		line = strings.TrimSpace(line)
		if len(line) > 300 {
			line = line[:300]
		}
		key := strings.ToLower(line)
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, Candidate{Summary: line, Satisfied: satisfied, Category: category})
		if len(result) == 12 {
			break
		}
	}
	return result
}

func candidateStatements(value string) []string {
	var result []string
	var current string
	flush := func() {
		if value := strings.TrimSpace(current); value != "" {
			result = append(result, value)
		}
		current = ""
	}
	for _, raw := range strings.Split(value, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "|") ||
			strings.HasPrefix(line, "```") {
			flush()
			continue
		}
		if listItemPrefix.MatchString(line) {
			flush()
			current = listItemPrefix.ReplaceAllString(line, "")
			continue
		}
		if current == "" {
			current = line
		} else {
			current += " " + line
		}
	}
	flush()
	return result
}
