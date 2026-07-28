package workscan

import (
	"sort"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/model"
	"github.com/jamesonstone/hyperlite/internal/threadstate"
)

func applyCachedInferences(state *threadstate.State, threads []model.Thread) {
	for index := range threads {
		thread := &threads[index]
		evidenceDigest := threadstate.EvidenceDigest(*thread)
		inference, found := threadstate.CachedInference(*state, thread.ID, evidenceDigest)
		if !found {
			thread.InferenceStatus = "pending"
			continue
		}
		applyInference(thread, inference)
		thread.InferenceStatus = "current"
	}
}

func applyInference(thread *model.Thread, inference model.InferenceThread) {
	if strings.TrimSpace(inference.Goal.Text) != "" {
		thread.Goal = strings.TrimSpace(inference.Goal.Text)
	}
	if strings.TrimSpace(inference.Rationale.Text) != "" {
		thread.Rationale = strings.TrimSpace(inference.Rationale.Text)
	}
	thread.Implications = append(thread.Implications, inference.Implications...)
	thread.Obligations = append(thread.Obligations, inference.Obligations...)
	for _, relation := range inference.Relations {
		thread.Dependencies = append(thread.Dependencies, model.ThreadRelation{
			Kind: relation.Kind, TargetThreadID: relation.TargetThreadID,
			Target: relation.Target, Basis: relation.Basis, Confidence: relation.Confidence,
			EvidenceIDs: append([]string{}, relation.EvidenceIDs...),
		})
	}
	if inference.ReviewSignificant && strings.TrimSpace(inference.ReviewSummary.Text) != "" {
		thread.Implications = append(thread.Implications, model.ThreadImplication{
			Summary:  strings.TrimSpace(inference.ReviewSummary.Text),
			Category: "review_decision", Basis: model.BasisExtracted,
			Confidence:  inference.Confidence,
			EvidenceIDs: append([]string{}, inference.ReviewSummary.EvidenceIDs...),
		})
	}
	if inference.Confidence > 0 {
		thread.Confidence = inference.Confidence
	}
	sortRelations(thread.Dependencies)
}

func resolveRelations(threads []model.Thread) {
	aliases := make(map[string]string)
	for _, thread := range threads {
		aliases[thread.ID] = thread.ID
		for _, alias := range thread.Aliases {
			aliases[alias] = thread.ID
		}
	}
	for threadIndex := range threads {
		for relationIndex := range threads[threadIndex].Dependencies {
			relation := &threads[threadIndex].Dependencies[relationIndex]
			if relation.TargetThreadID != "" {
				continue
			}
			if id, exists := aliases[relation.Target]; exists {
				relation.TargetThreadID = id
			}
		}
	}
	addEvidenceMentionHypotheses(threads)
}

func addEvidenceMentionHypotheses(threads []model.Thread) {
	targets := make(map[string]int)
	for index, thread := range threads {
		for _, repository := range thread.Repositories {
			previous, found := targets[repository]
			if !found || threadTargetScore(thread) > threadTargetScore(threads[previous]) {
				targets[repository] = index
			}
		}
	}
	for sourceIndex := range threads {
		source := &threads[sourceIndex]
		for repository, targetIndex := range targets {
			if sourceIndex == targetIndex {
				continue
			}
			target := threads[targetIndex]
			if sharesRepository(*source, target) {
				continue
			}
			name := repository
			if slash := strings.LastIndex(name, "/"); slash >= 0 {
				name = name[slash+1:]
			}
			evidenceIDs := mentionedByEvidence(source.Evidence, name)
			if len(evidenceIDs) == 0 || hasRelationTarget(source.Dependencies, target.ID) {
				continue
			}
			source.Dependencies = append(source.Dependencies, model.ThreadRelation{
				Kind: model.RelationAffects, TargetThreadID: target.ID, Target: repository,
				Basis: model.BasisHypothesis, Confidence: 0.45, EvidenceIDs: evidenceIDs,
			})
		}
		sortRelations(source.Dependencies)
	}
}

func sortRelations(values []model.ThreadRelation) {
	sort.Slice(values, func(i, j int) bool {
		left, right := values[i], values[j]
		if left.Kind != right.Kind {
			return left.Kind < right.Kind
		}
		if left.Target != right.Target {
			return left.Target < right.Target
		}
		if left.TargetThreadID != right.TargetThreadID {
			return left.TargetThreadID < right.TargetThreadID
		}
		if left.Basis != right.Basis {
			return left.Basis < right.Basis
		}
		if left.Confidence != right.Confidence {
			return left.Confidence < right.Confidence
		}
		return strings.Join(left.EvidenceIDs, "\x1f") < strings.Join(right.EvidenceIDs, "\x1f")
	})
}

func threadTargetScore(thread model.Thread) int {
	score := 0
	if thread.Active {
		score += 100
	}
	switch {
	case strings.HasPrefix(thread.ID, "issue:"):
		score += 30
	case strings.HasPrefix(thread.ID, "spec:"):
		score += 20
	case strings.HasPrefix(thread.ID, "pr:"):
		score += 10
	}
	return score
}

func sharesRepository(left, right model.Thread) bool {
	for _, leftRepository := range left.Repositories {
		for _, rightRepository := range right.Repositories {
			if leftRepository == rightRepository {
				return true
			}
		}
	}
	return false
}

func mentionedByEvidence(evidence []model.EvidenceRef, repository string) []string {
	needle := normalizedMention(repository)
	if needle == "" {
		return nil
	}
	var result []string
	for _, item := range evidence {
		if item.Kind != "spec" {
			continue
		}
		haystack := " " + normalizedMention(item.Excerpt) + " "
		if strings.Contains(haystack, " "+needle+" ") {
			result = append(result, item.ID)
		}
	}
	return result
}

func normalizedMention(value string) string {
	value = strings.ToLower(strings.ReplaceAll(value, "-", " "))
	var builder strings.Builder
	space := true
	for _, character := range value {
		if (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') {
			builder.WriteRune(character)
			space = false
		} else if !space {
			builder.WriteByte(' ')
			space = true
		}
	}
	return strings.TrimSpace(builder.String())
}

func hasRelationTarget(relations []model.ThreadRelation, target string) bool {
	for _, relation := range relations {
		if relation.TargetThreadID == target {
			return true
		}
	}
	return false
}
