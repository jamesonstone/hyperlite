package memoryscan

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
)

const maxSectionBytes = 16 * 1024

var (
	githubIssueURL  = regexp.MustCompile(`https://github\.com/[^/\s]+/[^/\s]+/issues/\d+`)
	localIssueRef   = regexp.MustCompile("(?i)\\bissue\\s+`?#(\\d+)`?")
	branchIssueRef  = regexp.MustCompile(`(?i)\bGH-(\d+)\b`)
	listItemPrefix  = regexp.MustCompile(`^(?:[-*]\s+|\d+[.)]\s+)`)
	obligationWord  = regexp.MustCompile(`(?i)\b(deploy|deployment|infrastructure|migration|production|provision|activate|rollout|postgres|s3|cloudformation|ecs|certificate|secret|runbook)\b`)
	implicationWord = regexp.MustCompile(`(?i)\b(public|security|breaking|authority|ownership|owns|must|production|infrastructure|migration|external|operational)\b`)
)

type frontmatter struct {
	Phase   string `yaml:"phase"`
	Feature struct {
		ID   string `yaml:"id"`
		Slug string `yaml:"slug"`
	} `yaml:"feature"`
	References []map[string]any `yaml:"references"`
}

func Scan(repositoryPath string) Result {
	root, err := filepath.Abs(repositoryPath)
	if err != nil {
		return Result{Diagnostics: []Diagnostic{{Path: repositoryPath, Message: err.Error()}}}
	}
	phases := progressPhases(root)
	paths, err := filepath.Glob(filepath.Join(root, "docs", "specs", "*", "SPEC.md"))
	if err != nil {
		return Result{Diagnostics: []Diagnostic{{Path: "docs/specs", Message: err.Error()}}}
	}
	sort.Strings(paths)
	result := Result{Documents: []Document{}, Diagnostics: []Diagnostic{}}
	for _, path := range paths {
		document, diagnostics := loadDocument(root, path, phases)
		result.Diagnostics = append(result.Diagnostics, diagnostics...)
		if document.ID != "" {
			result.Documents = append(result.Documents, document)
		}
	}
	markSelected(result.Documents)
	return result
}

func markSelected(documents []Document) {
	for index := range documents {
		switch strings.ToLower(strings.TrimSpace(documents[index].Phase)) {
		case "brainstorm", "research", "clarify", "spec", "plan", "implement", "implementation",
			"validate", "delivery", "operationalize", "operationalizing", "reflect", "reflection":
			documents[index].Selected = true
		}
	}
}

func loadDocument(root, path string, phases map[string]string) (Document, []Diagnostic) {
	relative, err := filepath.Rel(root, path)
	if err != nil {
		return Document{}, []Diagnostic{{Path: path, Message: err.Error()}}
	}
	relative = filepath.ToSlash(relative)
	contents, err := os.ReadFile(path)
	if err != nil {
		return Document{}, []Diagnostic{{Path: relative, Message: err.Error()}}
	}
	info, statErr := os.Stat(path)
	if statErr != nil {
		return Document{}, []Diagnostic{{Path: relative, Message: statErr.Error()}}
	}
	header, body, err := splitFrontmatter(contents)
	if err != nil {
		return Document{}, []Diagnostic{{Path: relative, Message: err.Error()}}
	}
	var metadata frontmatter
	if err := yaml.Unmarshal(header, &metadata); err != nil {
		return Document{}, []Diagnostic{{Path: relative, Message: "decode front matter: " + err.Error()}}
	}
	if metadata.Feature.ID == "" {
		return Document{}, []Diagnostic{{Path: relative, Message: "feature.id is required"}}
	}
	sections, title := markdownSections(body)
	phase := strings.TrimSpace(metadata.Phase)
	if phase == "" {
		phase = phases[metadata.Feature.ID]
	}
	document := Document{
		ID:             "spec:" + metadata.Feature.ID,
		FeatureID:      metadata.Feature.ID,
		Slug:           metadata.Feature.Slug,
		Title:          title,
		Phase:          phase,
		RepositoryRoot: root,
		Path:           relative,
		Purpose:        section(sections, "PURPOSE", "THESIS", "SUMMARY"),
		Context:        joinSections(sections, "CONTEXT", "CURRENT STATE", "AUTHORITY"),
		Plan:           section(sections, "ACCEPTED PLAN", "IMPLEMENTATION PLAN"),
		Decisions:      section(sections, "DECISIONS"),
		Outcome:        section(sections, "OUTCOME"),
		UpdatedAt:      info.ModTime(),
	}
	document.References = parseReferences(metadata.References)
	document.IssueURLs = issueURLs(document.References, string(contents))
	document.IssueNumbers = issueNumbers(section(sections, "DELIVERY DECISION"))
	if len(document.IssueNumbers) == 0 {
		document.IssueNumbers = issueNumbers(string(contents))
	}
	requirements := section(sections, "REQUIREMENTS")
	document.Obligations = candidates(requirements+"\n"+document.Plan, obligationWord, "operational")
	if isDeliveredPhase(document.Phase) {
		for index := range document.Obligations {
			document.Obligations[index].Satisfied = true
		}
	}
	document.Implications = candidates(joinSections(
		sections, "CONTEXT", "AUTHORITY", "INFRASTRUCTURE CONTRACT",
		"SIMULATION AND COMPATIBILITY", "DECISIONS", "REFLECTION NOTES", "DELIVERY DECISION",
	), implicationWord, "material")
	return document, nil
}

func issueNumbers(contents string) []int {
	issues := make(map[int]struct{})
	for _, match := range localIssueRef.FindAllStringSubmatch(contents, -1) {
		number, err := strconv.Atoi(match[1])
		if err == nil && number > 0 {
			issues[number] = struct{}{}
		}
	}
	branches := make(map[int]struct{})
	for _, match := range branchIssueRef.FindAllStringSubmatch(contents, -1) {
		number, err := strconv.Atoi(match[1])
		if err == nil && number > 0 {
			branches[number] = struct{}{}
		}
	}
	if len(branches) > 0 {
		matched := make(map[int]struct{})
		for number := range issues {
			if _, exists := branches[number]; exists {
				matched[number] = struct{}{}
			}
		}
		if len(matched) > 0 {
			issues = matched
		}
	}
	result := make([]int, 0, len(issues))
	for number := range issues {
		result = append(result, number)
	}
	sort.Ints(result)
	return result
}

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

func parseReferences(values []map[string]any) []Reference {
	result := make([]Reference, 0, len(values))
	for _, value := range values {
		target, _ := value["target"].(string)
		if strings.TrimSpace(target) == "" {
			continue
		}
		result = append(result, Reference{
			ID: text(value["id"]), Type: text(value["type"]),
			Target: strings.TrimSpace(target), Relation: text(value["relation"]),
		})
	}
	return result
}

func text(value any) string {
	text, _ := value.(string)
	return strings.TrimSpace(text)
}

func issueURLs(references []Reference, contents string) []string {
	seen := make(map[string]struct{})
	for _, reference := range references {
		if githubIssueURL.MatchString(reference.Target) {
			seen[githubIssueURL.FindString(reference.Target)] = struct{}{}
		}
	}
	for _, match := range githubIssueURL.FindAllString(contents, -1) {
		seen[match] = struct{}{}
	}
	result := make([]string, 0, len(seen))
	for value := range seen {
		result = append(result, value)
	}
	sort.Strings(result)
	return result
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

func isDeliveredPhase(phase string) bool {
	switch strings.ToLower(strings.TrimSpace(phase)) {
	case "deliver", "complete", "removed":
		return true
	default:
		return false
	}
}

func progressPhases(root string) map[string]string {
	contents, err := os.ReadFile(filepath.Join(root, "docs", "PROJECT_PROGRESS_SUMMARY.md"))
	if err != nil {
		return map[string]string{}
	}
	result := make(map[string]string)
	for _, line := range strings.Split(string(contents), "\n") {
		if !strings.HasPrefix(strings.TrimSpace(line), "|") {
			continue
		}
		parts := strings.Split(line, "|")
		if len(parts) < 5 {
			continue
		}
		id := strings.Trim(strings.TrimSpace(parts[1]), "`")
		if matched, _ := regexp.MatchString(`^\d{4}$`, id); !matched {
			continue
		}
		for _, candidate := range parts[2:] {
			phase := strings.ToLower(strings.Trim(strings.TrimSpace(candidate), "`"))
			switch phase {
			case "brainstorm", "research", "clarify", "spec", "plan", "implement", "implementation",
				"validate", "deliver", "delivery", "operationalize", "operationalizing",
				"reflect", "reflection", "complete", "removed":
				result[id] = phase
			}
		}
	}
	return result
}

func (d Document) ReadReferencedDocuments(root string) []Document {
	var result []Document
	for _, reference := range d.References {
		if strings.HasPrefix(reference.Target, "http://") || strings.HasPrefix(reference.Target, "https://") ||
			!strings.HasSuffix(strings.ToLower(reference.Target), ".md") {
			continue
		}
		path := referencedPath(root, d.Path, reference.Target)
		relative, err := filepath.Rel(root, path)
		if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			continue
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		info, err := os.Stat(path)
		if err != nil {
			continue
		}
		excerpt := strings.TrimSpace(string(contents))
		if len(excerpt) > maxSectionBytes {
			excerpt = excerpt[:maxSectionBytes]
		}
		result = append(result, Document{
			ID: "doc:" + filepath.ToSlash(relative), Title: filepath.Base(path),
			RepositoryRoot: root, Path: filepath.ToSlash(relative),
			Purpose: excerpt, UpdatedAt: info.ModTime(),
		})
	}
	return result
}

func referencedPath(root, documentPath, target string) string {
	target = filepath.FromSlash(target)
	if filepath.IsAbs(target) {
		return filepath.Clean(target)
	}
	if target == "docs" || strings.HasPrefix(target, "docs"+string(filepath.Separator)) {
		return filepath.Clean(filepath.Join(root, target))
	}
	return filepath.Clean(filepath.Join(filepath.Dir(filepath.Join(root, documentPath)), target))
}

func (d Document) Validate() error {
	if d.ID == "" || d.Path == "" {
		return fmt.Errorf("document identity is incomplete")
	}
	return nil
}
