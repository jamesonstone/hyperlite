package memoryscan

import (
	"os"
	"path/filepath"
	"strings"

	"go.yaml.in/yaml/v3"
)

type frontmatter struct {
	Phase   string `yaml:"phase"`
	Feature struct {
		ID   string `yaml:"id"`
		Slug string `yaml:"slug"`
	} `yaml:"feature"`
	References []map[string]any `yaml:"references"`
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

func isDeliveredPhase(phase string) bool {
	switch strings.ToLower(strings.TrimSpace(phase)) {
	case "deliver", "complete", "removed":
		return true
	default:
		return false
	}
}
