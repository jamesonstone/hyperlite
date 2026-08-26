package prindex

import (
	"context"
	"strings"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
)

func TestGitHubClientMapsMergeConflicts(t *testing.T) {
	cases := []struct {
		mergeable string
		want      bool
	}{
		{mergeable: "CONFLICTING", want: true},
		{mergeable: "MERGEABLE", want: false},
		{mergeable: "UNKNOWN", want: false},
		{mergeable: "", want: false},
	}
	for _, test := range cases {
		t.Run(test.mergeable, func(t *testing.T) {
			runner := &graphQLRunner{respond: func(query string, _ int) ([]byte, error) {
				if !strings.Contains(query, "mergeable") {
					t.Fatalf("query missing mergeable: %s", query)
				}
				page := repositoryPage(1, false, "")
				nodes := page["pullRequests"].(map[string]any)["nodes"].([]map[string]any)
				if test.mergeable != "" {
					nodes[0]["mergeable"] = test.mergeable
				}
				return responseJSON(map[string]any{"repository0": page}, nil), nil
			}}
			got := (GitHubClient{Runner: runner}).ListOpen(
				context.Background(), []config.Repository{{GitHub: "owner/one"}},
			).Repositories["owner/one"]
			if got.Error != "" || len(got.PullRequests) != 1 ||
				got.PullRequests[0].HasMergeConflict != test.want {
				t.Fatalf("mergeable %q = %#v", test.mergeable, got)
			}
		})
	}
}
