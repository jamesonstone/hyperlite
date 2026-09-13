package prindex

import (
	"context"
	"errors"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestWorkflowNameFromYAML(t *testing.T) {
	tests := []struct {
		text  string
		want  string
		found bool
	}{
		{"name: ci\non: push\n", "ci", true},
		{"# comment\nname: \"Deploy Web\" # prod\n", "Deploy Web", true},
		{"name: 'quoted # not comment'\n", "quoted # not comment", true},
		{"name: deploy # trailing\n", "deploy", true},
		{"on: push\njobs:\n  build:\n    name: inner\n", "", false},
		{"name:\n", "", false},
		{"name: # only comment\n", "", false},
	}
	for _, test := range tests {
		got, found := workflowNameFromYAML(test.text)
		if got != test.want || found != test.found {
			t.Fatalf("workflowNameFromYAML(%q) = %q %v, want %q %v", test.text, got, found, test.want, test.found)
		}
	}
}

func TestParseWorkflowCatalogKeepsTreeOrderAndFallsBack(t *testing.T) {
	entries := []rawWorkflowTreeEntry{
		{Name: "README.md", Type: "blob"},
		{Name: "templates", Type: "tree"},
		{Name: "ci.yaml", Type: "blob", Object: &struct {
			Text        string `json:"text"`
			IsTruncated bool   `json:"isTruncated"`
		}{Text: "name: ci\n"}},
		{Name: "deploy.yml", Type: "blob", Object: &struct {
			Text        string `json:"text"`
			IsTruncated bool   `json:"isTruncated"`
		}{Text: "name: Deploy\n", IsTruncated: true}},
		{Name: "release.yaml", Type: "blob"},
	}
	catalog := parseWorkflowCatalog("owner/repo", entries)
	if len(catalog) != 3 {
		t.Fatalf("catalog = %#v", catalog)
	}
	if catalog[0].File != "ci.yaml" || catalog[0].Name != "ci" ||
		catalog[0].URL != "https://github.com/owner/repo/actions/workflows/ci.yaml" {
		t.Fatalf("ci = %#v", catalog[0])
	}
	if catalog[1].Name != "deploy" || catalog[2].Name != "release" {
		t.Fatalf("fallbacks = %#v", catalog[1:])
	}
}

func TestFetchCatalogsBatchesAndScopesErrors(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		return responseJSONWithRateLimit(map[string]any{
			"repository0": map[string]any{"object": map[string]any{
				"oid": "tree-1",
				"entries": []map[string]any{{
					"name": "ci.yaml", "type": "blob",
					"object": map[string]any{"text": "name: ci\n", "isTruncated": false},
				}},
			}},
			"repository1": map[string]any{"object": nil},
			"repository2": nil,
		}, []map[string]any{{
			"message": "Could not resolve to a Repository", "path": []any{"repository2"},
		}}, githubRateLimit(10, 1, 3)), nil
	}}
	client := GitHubClient{Runner: runner}
	result := client.FetchCatalogs(context.Background(), []config.Repository{
		{GitHub: "owner/one"}, {GitHub: "owner/two"}, {GitHub: "owner/three"},
	})
	if runner.calls != 1 {
		t.Fatalf("calls = %d", runner.calls)
	}
	one := result.Repositories["owner/one"]
	if one.Error != "" || one.TreeOID != "tree-1" || len(one.Catalog) != 1 || one.Catalog[0].Name != "ci" {
		t.Fatalf("one = %#v", one)
	}
	two := result.Repositories["owner/two"]
	if two.Error != "" || two.TreeOID != "" || len(two.Catalog) != 0 {
		t.Fatalf("two = %#v", two)
	}
	if result.Repositories["owner/three"].Error != "Could not resolve to a Repository" {
		t.Fatalf("three = %#v", result.Repositories["owner/three"])
	}
	if result.RateLimit == nil || result.RateLimit.Used != 10 {
		t.Fatalf("rate limit = %#v", result.RateLimit)
	}
}

func TestFetchCatalogsCommandFailureScopesToBatch(t *testing.T) {
	runner := &graphQLRunner{respond: func(_ string, _ int) ([]byte, error) {
		return nil, errors.New("gh unavailable")
	}}
	result := GitHubClient{Runner: runner}.FetchCatalogs(
		context.Background(), []config.Repository{{GitHub: "owner/one"}},
	)
	if result.Repositories["owner/one"].Error != "gh unavailable" {
		t.Fatalf("result = %#v", result)
	}
}
