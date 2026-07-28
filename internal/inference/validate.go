package inference

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sort"
	"strings"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func validate(inputs []model.Thread, outputs []model.InferenceThread) ([]model.InferenceThread, error) {
	threads := make(map[string]model.Thread, len(inputs))
	allEvidence := make(map[string]struct{})
	for _, thread := range inputs {
		threads[thread.ID] = thread
		for _, evidence := range thread.Evidence {
			allEvidence[evidence.ID] = struct{}{}
		}
	}
	seen := make(map[string]struct{}, len(outputs))
	result := make([]model.InferenceThread, 0, len(outputs))
	for _, output := range outputs {
		input, exists := threads[output.ThreadID]
		if !exists {
			return nil, fmt.Errorf("inference references unknown thread %q", output.ThreadID)
		}
		if _, duplicate := seen[output.ThreadID]; duplicate {
			return nil, fmt.Errorf("inference repeats thread %q", output.ThreadID)
		}
		seen[output.ThreadID] = struct{}{}
		evidence := make(map[string]struct{}, len(input.Evidence))
		for _, item := range input.Evidence {
			evidence[item.ID] = struct{}{}
		}
		if err := validateClaim(output.Goal, evidence, "goal"); err != nil {
			return nil, fmt.Errorf("thread %s: %w", output.ThreadID, err)
		}
		if err := validateClaim(output.Rationale, evidence, "rationale"); err != nil {
			return nil, fmt.Errorf("thread %s: %w", output.ThreadID, err)
		}
		if err := validateClaim(output.ReviewSummary, evidence, "review summary"); err != nil {
			return nil, fmt.Errorf("thread %s: %w", output.ThreadID, err)
		}
		for index := range output.Implications {
			value := &output.Implications[index]
			if err := validateEvidence(value.Summary, value.EvidenceIDs, evidence); err != nil {
				return nil, fmt.Errorf("thread %s implication: %w", output.ThreadID, err)
			}
			if err := validateBasis(value.Basis); err != nil {
				return nil, err
			}
			value.Confidence = normalizedConfidence(value.Confidence)
		}
		for index := range output.Obligations {
			value := &output.Obligations[index]
			if err := validateEvidence(value.Summary, value.EvidenceIDs, evidence); err != nil {
				return nil, fmt.Errorf("thread %s obligation: %w", output.ThreadID, err)
			}
			if err := validateBasis(value.Basis); err != nil {
				return nil, err
			}
			if value.ID == "" {
				value.ID = inferenceID("obligation", output.ThreadID, value.Summary)
			}
			value.Confidence = normalizedConfidence(value.Confidence)
		}
		for index := range output.Relations {
			value := &output.Relations[index]
			if value.TargetThreadID != "" {
				if _, exists := threads[value.TargetThreadID]; !exists {
					return nil, fmt.Errorf("thread %s relation references unknown target %q", output.ThreadID, value.TargetThreadID)
				}
			}
			if err := validateRelationKind(value.Kind); err != nil {
				return nil, err
			}
			if err := validateBasis(value.Basis); err != nil {
				return nil, err
			}
			if err := validateEvidence(value.Target, value.EvidenceIDs, allEvidence); err != nil {
				return nil, fmt.Errorf("thread %s relation: %w", output.ThreadID, err)
			}
			value.Confidence = normalizedConfidence(value.Confidence)
		}
		output.Confidence = normalizedConfidence(output.Confidence)
		sort.Strings(output.Goal.EvidenceIDs)
		sort.Strings(output.Rationale.EvidenceIDs)
		sort.Strings(output.ReviewSummary.EvidenceIDs)
		result = append(result, output)
	}
	if len(result) != len(inputs) {
		return nil, fmt.Errorf("inference returned %d thread(s), expected %d", len(result), len(inputs))
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ThreadID < result[j].ThreadID })
	return result, nil
}

func validateClaim(value model.InferenceClaim, evidence map[string]struct{}, name string) error {
	if strings.TrimSpace(value.Text) == "" {
		return nil
	}
	if err := validateEvidence(value.Text, value.EvidenceIDs, evidence); err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	return nil
}

func validateEvidence(text string, ids []string, evidence map[string]struct{}) error {
	if strings.TrimSpace(text) == "" {
		return nil
	}
	if len(ids) == 0 {
		return fmt.Errorf("claim %q has no evidence", boundedText(text))
	}
	for _, id := range ids {
		if _, exists := evidence[id]; !exists {
			return fmt.Errorf("claim %q cites unknown evidence %q", boundedText(text), id)
		}
	}
	return nil
}

func validateBasis(value model.EvidenceBasis) error {
	switch value {
	case model.BasisExtracted, model.BasisHypothesis:
		return nil
	default:
		return fmt.Errorf("model output cannot use evidence basis %q", value)
	}
}

func validateRelationKind(value model.RelationKind) error {
	switch value {
	case model.RelationDependsOn, model.RelationMustPrecede, model.RelationAffects, model.RelationSupports:
		return nil
	default:
		return fmt.Errorf("invalid relation kind %q", value)
	}
}

func normalizedConfidence(value float64) float64 {
	if value < 0 {
		return 0
	}
	if value > 1 {
		return 1
	}
	return value
}

func inferenceID(prefix string, values ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(values, "\x1f")))
	return prefix + ":" + hex.EncodeToString(sum[:8])
}

func boundedText(value string) string {
	value = strings.TrimSpace(value)
	if len(value) > 80 {
		return value[:80] + "…"
	}
	return value
}
