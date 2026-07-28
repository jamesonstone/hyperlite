package threadstate

import (
	"regexp"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/model"
)

var boundaryAction = regexp.MustCompile(
	`(?i)\b(change|changes|changing|deploy(?:s|ed|ing)?|provision(?:s|ed|ing)?|` +
		`migrat(?:e|es|ed|ing)|activat(?:e|es|ed|ing)|enabl(?:e|es|ed|ing)|` +
		`switch(?:es|ed|ing)?|replac(?:e|es|ed|ing)|remov(?:e|es|ed|ing)|` +
		`delet(?:e|es|ed|ing)|publish(?:es|ed|ing)?|expos(?:e|es|ed|ing)|` +
		`break(?:s|ing)?|cutover|rollout|rotat(?:e|es|ed|ing))\b`,
)

var boundaryHistoricalContext = regexp.MustCompile(
	`(?i)\b(history|historical|previously|formerly|already|past|prior|earlier)\b`,
)

var boundaryPastAction = regexp.MustCompile(
	`(?i)\b(changed|deployed|provisioned|migrated|activated|enabled|switched|` +
		`replaced|removed|deleted|published|exposed|rotated)\b`,
)

var boundaryProspectiveContext = regexp.MustCompile(
	`(?i)\b(must|should|will|needs?|requires?|pending|next|about\s+to|not\s+yet)\b`,
)

var boundaryCompletedContext = regexp.MustCompile(
	`(?i)\b(complete|completed|done|finished|delivered|implemented|resolved|closed)\b`,
)

var boundaryClauses = regexp.MustCompile(
	`(?i)(?:[.;\n]+|\s+(?:but|while|whereas)\s+)`,
)

func hasActionableBoundary(thread model.Thread) bool {
	for _, implication := range thread.Implications {
		if boundaryCategory(implication.Category) &&
			actionableBoundaryStatement(implication.Summary) {
			return true
		}
	}
	for _, obligation := range thread.Obligations {
		if !obligation.Satisfied && actionableBoundaryStatement(obligation.Summary) {
			return true
		}
	}
	return false
}

func boundaryCategory(category string) bool {
	switch category {
	case "production", "security", "migration", "infrastructure", "operational":
		return true
	default:
		return false
	}
}

func actionableBoundaryStatement(value string) bool {
	for _, clause := range boundaryClauses.Split(value, -1) {
		if actionableBoundaryClause(clause) {
			return true
		}
	}
	return false
}

func actionableBoundaryClause(value string) bool {
	lower := strings.ToLower(strings.TrimSpace(value))
	if lower == "" || !boundaryAction.MatchString(lower) {
		return false
	}
	if strings.HasPrefix(lower, "no ") {
		return false
	}
	for _, negative := range []string{
		"must not", "never ", "does not", "do not", "will not",
		"not required", "future work",
	} {
		if strings.Contains(lower, negative) {
			return false
		}
	}
	if boundaryCompletedContext.MatchString(lower) {
		return false
	}
	if (boundaryHistoricalContext.MatchString(lower) ||
		boundaryPastAction.MatchString(lower)) &&
		!boundaryProspectiveContext.MatchString(lower) {
		return false
	}
	return true
}

func boundaryEvidence(thread model.Thread) []string {
	var result []string
	for _, implication := range thread.Implications {
		if boundaryCategory(implication.Category) &&
			actionableBoundaryStatement(implication.Summary) {
			result = append(result, implication.EvidenceIDs...)
		}
	}
	for _, obligation := range thread.Obligations {
		if !obligation.Satisfied && actionableBoundaryStatement(obligation.Summary) {
			result = append(result, obligation.EvidenceIDs...)
		}
	}
	return uniqueStrings(result)
}
