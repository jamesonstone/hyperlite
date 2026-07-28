package memoryscan

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

const maxSectionBytes = 16 * 1024

var (
	githubIssueURL = regexp.MustCompile(`https://github\.com/[^/\s]+/[^/\s]+/issues/\d+`)
	localIssueRef  = regexp.MustCompile("(?i)\\bissue\\s+`?#(\\d+)`?")
	branchIssueRef = regexp.MustCompile(`(?i)\bGH-(\d+)\b`)
)

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
