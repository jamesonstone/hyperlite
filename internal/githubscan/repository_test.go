package githubscan

import (
	"context"
	"fmt"
	"testing"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestCollectAllKeepsIssueEvidenceWhenPullRequestsFail(t *testing.T) {
	runner := &fixtureRunner{
		responses: map[string][]byte{
			"gh issue list": []byte(`[{"number":7,"title":"Queued","url":"https://github.com/owner/repo/issues/7","updatedAt":"2026-07-10T12:00:00Z","labels":[],"assignees":[]}]`),
		},
		failures: map[string]error{"gh pr list": fmt.Errorf("pull requests unavailable")},
	}
	collection := (Client{Runner: runner}).Collect(context.Background(), []config.Repository{{Name: "repo", GitHub: "owner/repo"}}, "all", "@me", 1)
	evidence := collection.Repositories["owner/repo"]
	if len(evidence.Issues) != 1 || len(evidence.Errors) != 1 || evidence.Errors[0].Stage != "github-prs" {
		t.Fatalf("evidence = %#v", evidence)
	}
}

func TestCollectRepositoryHydratesExactUnassignedIssueAnchor(t *testing.T) {
	runner := &fixtureRunner{responses: map[string][]byte{
		"gh pr list":    []byte(`[]`),
		"gh issue list": []byte(`[]`),
		"gh issue view": issueFixture,
	}}
	evidence := collectAnchors(runner, []int{7})
	if len(evidence.Errors) != 0 || len(evidence.Issues) != 1 ||
		evidence.Issues[0].Number != 7 || evidence.Issues[0].State != "OPEN" {
		t.Fatalf("evidence = %#v", evidence)
	}
	if runner.count("gh issue view") != 1 {
		t.Fatalf("calls = %v", runner.calls)
	}
}

func TestCollectRepositoryBoundsExactIssueHydration(t *testing.T) {
	runner := &fixtureRunner{responses: map[string][]byte{
		"gh pr list":    []byte(`[]`),
		"gh issue list": []byte(`[]`),
		"gh issue view": issueFixture,
	}}
	anchors := make([]int, anchorIssueLimit+1)
	for index := range anchors {
		anchors[index] = index + 100
	}
	evidence := collectAnchors(runner, anchors)
	if runner.count("gh issue view") != anchorIssueLimit ||
		len(evidence.Warnings) != 1 ||
		evidence.Warnings[0].Stage != "github-issues" {
		t.Fatalf("calls=%d evidence=%#v", runner.count("gh issue view"), evidence)
	}
}

func TestCollectRepositorySkipsKnownIssueAnchor(t *testing.T) {
	runner := &fixtureRunner{responses: map[string][]byte{
		"gh pr list":    []byte(`[]`),
		"gh issue list": []byte(`[{"number":7,"title":"Anchored goal","url":"https://github.com/owner/repo/issues/7","state":"OPEN","updatedAt":"2026-07-28T12:00:00Z","labels":[],"assignees":[]}]`),
	}}
	evidence := collectAnchors(runner, []int{7})
	if len(evidence.Issues) != 1 || runner.count("gh issue view") != 0 {
		t.Fatalf("evidence=%#v calls=%v", evidence, runner.calls)
	}
}

func collectAnchors(runner *fixtureRunner, anchors []int) model.RemoteEvidence {
	return (Client{Runner: runner}).CollectRepository(
		context.Background(),
		config.Repository{Name: "repo", GitHub: "owner/repo"},
		"mine",
		"@me",
		anchors,
	)
}

var issueFixture = []byte(`{
	"number":7,
	"title":"Anchored goal",
	"body":"Canonical issue",
	"url":"https://github.com/owner/repo/issues/7",
	"state":"OPEN",
	"updatedAt":"2026-07-28T12:00:00Z",
	"labels":[],
	"assignees":[]
}`)
