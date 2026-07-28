package threadbuild

import (
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func finalize(thread *model.Thread, hasSpec bool, issueNumber int, now time.Time) {
	thread.Aliases = unique(thread.Aliases)
	thread.Repositories = unique(thread.Repositories)
	thread.Artifacts = uniqueArtifacts(thread.Artifacts)
	sort.Slice(thread.Evidence, func(i, j int) bool { return thread.Evidence[i].ID < thread.Evidence[j].ID })
	sort.Slice(thread.Obligations, func(i, j int) bool { return thread.Obligations[i].ID < thread.Obligations[j].ID })
	sort.Slice(thread.Implications, func(i, j int) bool {
		if thread.Implications[i].Category != thread.Implications[j].Category {
			return thread.Implications[i].Category < thread.Implications[j].Category
		}
		return thread.Implications[i].Summary < thread.Implications[j].Summary
	})
	sort.Slice(thread.Dependencies, func(i, j int) bool {
		if thread.Dependencies[i].Kind != thread.Dependencies[j].Kind {
			return thread.Dependencies[i].Kind < thread.Dependencies[j].Kind
		}
		return thread.Dependencies[i].Target < thread.Dependencies[j].Target
	})
	if thread.Title == "" {
		thread.Title = thread.ID
	}
	if thread.Goal == "" {
		thread.Goal = thread.Title
	}
	if thread.Rationale == "" {
		thread.Rationale = "No durable rationale was found in the available evidence."
	}
	thread.Phase = derivedPhase(*thread, hasSpec, issueNumber)
	thread.Active = thread.Phase != model.ThreadComplete
	if !thread.Active {
		thread.UpdatedAt = latestTerminalArtifact(*thread)
	}
	thread.Confidence = confidence(*thread, hasSpec)
	if thread.Active && thread.UpdatedAt.IsZero() {
		thread.UpdatedAt = now
	}
}

func latestTerminalArtifact(thread model.Thread) time.Time {
	var latest time.Time
	for _, artifact := range thread.Artifacts {
		switch artifact.Kind {
		case model.ArtifactIssue, model.ArtifactPullRequest, model.ArtifactReview,
			model.ArtifactBranch, model.ArtifactWorktree:
			if artifact.UpdatedAt.After(latest) {
				latest = artifact.UpdatedAt
			}
		}
	}
	return latest
}

func derivedPhase(thread model.Thread, hasSpec bool, issueNumber int) model.ThreadPhase {
	hasOpenPR, hasDraftPR, hasMergedPR := false, false, false
	hasLocal, openIssue := false, false
	for _, artifact := range thread.Artifacts {
		switch artifact.Kind {
		case model.ArtifactPullRequest:
			switch strings.ToLower(artifact.State) {
			case "draft":
				hasDraftPR = true
			case "open":
				hasOpenPR = true
			case "merged":
				hasMergedPR = true
			}
		case model.ArtifactWorktree, model.ArtifactBranch:
			hasLocal = true
		case model.ArtifactIssue:
			openIssue = strings.EqualFold(artifact.State, "open")
		}
	}
	if hasOpenPR {
		return model.ThreadReviewing
	}
	if hasDraftPR {
		return model.ThreadImplementing
	}
	if (hasMergedPR || thread.Phase == model.ThreadComplete) &&
		(hasOpenObligations(thread) || openIssue) {
		return model.ThreadOperationalizing
	}
	if hasSpec && thread.Phase == model.ThreadComplete &&
		!hasOpenObligations(thread) && !openIssue {
		return model.ThreadComplete
	}
	if hasMergedPR {
		return model.ThreadReflecting
	}
	if hasLocal {
		return model.ThreadImplementing
	}
	if thread.Phase == model.ThreadReflecting {
		return model.ThreadReflecting
	}
	if hasSpec {
		if thread.Phase != "" {
			return thread.Phase
		}
		return model.ThreadPlanned
	}
	if openIssue {
		return model.ThreadShaping
	}
	if issueNumber > 0 {
		return model.ThreadReflecting
	}
	return model.ThreadImplementing
}

func phaseFromDocument(phase string) model.ThreadPhase {
	switch strings.ToLower(strings.TrimSpace(phase)) {
	case "brainstorm", "research", "clarify", "spec":
		return model.ThreadShaping
	case "plan":
		return model.ThreadPlanned
	case "implement", "implementation":
		return model.ThreadImplementing
	case "validate":
		return model.ThreadReviewing
	case "delivery", "operationalize", "operationalizing":
		return model.ThreadOperationalizing
	case "reflect", "reflection":
		return model.ThreadReflecting
	case "deliver", "complete", "removed":
		return model.ThreadComplete
	default:
		return model.ThreadPlanned
	}
}

func hasOpenObligations(thread model.Thread) bool {
	for _, obligation := range thread.Obligations {
		if !obligation.Satisfied {
			return true
		}
	}
	return false
}

func confidence(thread model.Thread, hasSpec bool) float64 {
	value := 0.45
	if hasSpec {
		value = 0.85
	}
	for _, artifact := range thread.Artifacts {
		if artifact.Kind == model.ArtifactIssue || artifact.Kind == model.ArtifactPullRequest {
			if value < 0.75 {
				value = 0.75
			}
		}
	}
	for _, evidence := range thread.Evidence {
		if evidence.Freshness == "stale" {
			value -= 0.25
			break
		}
	}
	if value < 0.1 {
		return 0.1
	}
	return value
}

func implicationCategory(value string) string {
	lower := strings.ToLower(value)
	switch {
	case strings.Contains(lower, "security") || strings.Contains(lower, "secret") || strings.Contains(lower, "auth"):
		return "security"
	case strings.Contains(lower, "migration") || strings.Contains(lower, "schema"):
		return "migration"
	case strings.Contains(lower, "infrastructure") || strings.Contains(lower, "cloudformation") ||
		strings.Contains(lower, "ecs") || strings.Contains(lower, "s3"):
		return "infrastructure"
	case strings.Contains(lower, "production") || strings.Contains(lower, "deploy") || strings.Contains(lower, "public"):
		return "production"
	default:
		return "material"
	}
}

func relationKind(value string) (model.RelationKind, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "depends_on", "depends-on", "requires":
		return model.RelationDependsOn, true
	case "must_precede", "must-precede", "precedes":
		return model.RelationMustPrecede, true
	case "affects", "impacts":
		return model.RelationAffects, true
	case "supports":
		return model.RelationSupports, true
	default:
		return "", false
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func humanize(value string) string {
	value = strings.TrimSpace(strings.ReplaceAll(value, "-", " "))
	if value == "" {
		return ""
	}
	return strings.ToUpper(value[:1]) + value[1:]
}

func firstParagraph(value string) string {
	value = strings.TrimSpace(value)
	if index := strings.Index(value, "\n\n"); index >= 0 {
		value = value[:index]
	}
	return bounded(value)
}

func bounded(value string) string {
	value = strings.TrimSpace(value)
	if len(value) > 4*1024 {
		return value[:4*1024]
	}
	return value
}

func joinExcerpt(values ...string) string {
	var present []string
	for _, value := range values {
		if value = strings.TrimSpace(value); value != "" {
			present = append(present, value)
		}
	}
	return bounded(strings.Join(present, "\n\n"))
}

func stableID(prefix string, values ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(values, "\x1f")))
	return prefix + ":" + hex.EncodeToString(sum[:8])
}

func unique(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		if strings.TrimSpace(value) == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}
