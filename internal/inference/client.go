package inference

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

const (
	defaultEndpoint = "http://127.0.0.1:11434/api/generate"
	maxPromptBytes  = 128 * 1024
)

type Client struct {
	HTTPClient *http.Client
	Endpoint   string
}

type ollamaRequest struct {
	Model   string         `json:"model"`
	Prompt  string         `json:"prompt"`
	Stream  bool           `json:"stream"`
	Format  string         `json:"format"`
	Options map[string]any `json:"options"`
}

type ollamaResponse struct {
	Response string `json:"response"`
}

type modelResponse struct {
	Threads []model.InferenceThread `json:"threads"`
}

type promptThread struct {
	ID       string              `json:"id"`
	Title    string              `json:"title"`
	Phase    model.ThreadPhase   `json:"phase"`
	Evidence []model.EvidenceRef `json:"evidence"`
}

func (c Client) Enrich(ctx context.Context, modelName string, threads []model.Thread) ([]model.InferenceThread, error) {
	if strings.TrimSpace(modelName) == "" {
		return nil, errors.New("local inference model is not configured")
	}
	prompt, err := buildPrompt(threads)
	if err != nil {
		return nil, err
	}
	requestBody, err := json.Marshal(ollamaRequest{
		Model: strings.TrimSpace(modelName), Prompt: prompt, Stream: false, Format: "json",
		Options: map[string]any{"temperature": 0},
	})
	if err != nil {
		return nil, fmt.Errorf("encode Ollama request: %w", err)
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint(), bytes.NewReader(requestBody))
	if err != nil {
		return nil, fmt.Errorf("create Ollama request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := c.client().Do(request)
	if err != nil {
		return nil, fmt.Errorf("call local Ollama: %w", err)
	}
	defer response.Body.Close()
	contents, err := io.ReadAll(io.LimitReader(response.Body, 2*1024*1024))
	if err != nil {
		return nil, fmt.Errorf("read Ollama response: %w", err)
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf("Ollama returned %s: %s", response.Status, strings.TrimSpace(string(contents)))
	}
	var envelope ollamaResponse
	if err := json.Unmarshal(contents, &envelope); err != nil {
		return nil, fmt.Errorf("decode Ollama envelope: %w", err)
	}
	var output modelResponse
	decoder := json.NewDecoder(strings.NewReader(envelope.Response))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&output); err != nil {
		return nil, fmt.Errorf("decode inference JSON: %w", err)
	}
	return validate(threads, output.Threads)
}

func buildPrompt(threads []model.Thread) (string, error) {
	values := make([]promptThread, 0, len(threads))
	for _, thread := range threads {
		if !thread.Active {
			continue
		}
		value := promptThread{ID: thread.ID, Title: thread.Title, Phase: thread.Phase}
		remaining := 32 * 1024
		for _, evidence := range thread.Evidence {
			if remaining <= 0 {
				break
			}
			if len(evidence.Excerpt) > remaining {
				evidence.Excerpt = evidence.Excerpt[:remaining]
			}
			remaining -= len(evidence.Excerpt)
			value.Evidence = append(value.Evidence, evidence)
		}
		values = append(values, value)
	}
	evidenceJSON, err := json.Marshal(values)
	if err != nil {
		return "", fmt.Errorf("encode inference evidence: %w", err)
	}
	if len(evidenceJSON) > maxPromptBytes {
		return "", fmt.Errorf("inference evidence exceeds %d bytes", maxPromptBytes)
	}
	instructions := `You synthesize coordination state from supplied evidence only.
Return JSON with top-level {"threads": [...]} and one item per input thread.
Each item uses: thread_id, goal {text,evidence_ids}, rationale {text,evidence_ids},
implications [{summary,category,basis,confidence,evidence_ids}],
obligations [{id,summary,satisfied,basis,confidence,evidence_ids}],
relations [{kind,target_thread_id,target,basis,confidence,evidence_ids}],
review_significant, review_summary {text,evidence_ids}, confidence.
Every non-empty claim must cite valid supplied evidence IDs. Basis is extracted
when the cited evidence asserts the claim and hypothesis otherwise. Semantic
relationships may relate threads but never merge them. Classify review as
significant only when it challenges architecture, direction, ownership,
security, production safety, migration, or another durable boundary; routine
code repair is not significant. Do not infer completion from a PR, branch, CI,
or agent lifecycle. Use empty values rather than inventing evidence.`
	return instructions + "\n\nEvidence:\n" + string(evidenceJSON), nil
}

func (c Client) endpoint() string {
	if strings.TrimSpace(c.Endpoint) != "" {
		return c.Endpoint
	}
	return defaultEndpoint
}

func (c Client) client() *http.Client {
	if c.HTTPClient != nil {
		return c.HTTPClient
	}
	return &http.Client{Timeout: 20 * time.Second}
}
