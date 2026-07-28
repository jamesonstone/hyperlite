package inference

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestClientRequiresCitedSchemaValidClaims(t *testing.T) {
	var prompt string
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		var body ollamaRequest
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		prompt = body.Prompt
		response := `{"threads":[{
			"thread_id":"issue:owner/r2#10",
			"goal":{"text":"Store durable payloads","evidence_ids":["spec:r2"]},
			"rationale":{"text":"Separate storage ownership","evidence_ids":["spec:r2"]},
			"implications":[{"summary":"Production storage changes","category":"production","basis":"extracted","confidence":0.9,"evidence_ids":["spec:r2"]}],
			"obligations":[{"id":"","summary":"Deploy the bucket","satisfied":false,"basis":"extracted","confidence":0.8,"evidence_ids":["spec:r2"]}],
			"relations":[],
			"review_significant":false,
			"review_summary":{"text":"","evidence_ids":[]},
			"confidence":0.9
		}]}`
		_ = json.NewEncoder(writer).Encode(ollamaResponse{Response: response})
	}))
	defer server.Close()
	thread := inferenceThread()
	values, err := (Client{Endpoint: server.URL, HTTPClient: server.Client()}).Enrich(
		t.Context(), "qwen-local", []model.Thread{thread},
	)
	if err != nil {
		t.Fatal(err)
	}
	if len(values) != 1 || values[0].Obligations[0].ID == "" {
		t.Fatalf("values = %#v", values)
	}
	if !strings.Contains(prompt, `"id":"spec:r2"`) || !strings.Contains(prompt, "routine") {
		t.Fatalf("bounded prompt omitted evidence contract: %s", prompt)
	}
}

func TestClientRejectsUncitedAndAuthoritativeModelClaims(t *testing.T) {
	tests := []struct {
		name     string
		response string
		want     string
	}{
		{
			name: "uncited",
			response: `{"threads":[{
				"thread_id":"issue:owner/r2#10",
				"goal":{"text":"Invented","evidence_ids":[]},
				"rationale":{"text":"","evidence_ids":[]},"implications":[],"obligations":[],"relations":[],
				"review_significant":false,"review_summary":{"text":"","evidence_ids":[]},"confidence":0.5
			}]}`,
			want: "has no evidence",
		},
		{
			name: "explicit basis",
			response: `{"threads":[{
				"thread_id":"issue:owner/r2#10",
				"goal":{"text":"","evidence_ids":[]},"rationale":{"text":"","evidence_ids":[]},
				"implications":[{"summary":"Claim","category":"production","basis":"explicit","confidence":1,"evidence_ids":["spec:r2"]}],
				"obligations":[],"relations":[],"review_significant":false,
				"review_summary":{"text":"","evidence_ids":[]},"confidence":0.5
			}]}`,
			want: "cannot use evidence basis",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
				_ = json.NewEncoder(writer).Encode(ollamaResponse{Response: test.response})
			}))
			defer server.Close()
			_, err := (Client{Endpoint: server.URL, HTTPClient: server.Client()}).Enrich(
				t.Context(), "local", []model.Thread{inferenceThread()},
			)
			if err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("error = %v, want %q", err, test.want)
			}
		})
	}
}

func inferenceThread() model.Thread {
	return model.Thread{
		ID: "issue:owner/r2#10", Title: "R2", Active: true, Phase: model.ThreadReviewing,
		Evidence: []model.EvidenceRef{{
			ID: "spec:r2", Source: "repository_memory", Repository: "owner/r2",
			Kind: "spec", Title: "R2", Excerpt: "Deploy the production bucket.", Freshness: "current",
		}},
	}
}
