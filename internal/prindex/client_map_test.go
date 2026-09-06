package prindex

import (
	"encoding/json"
	"testing"
)

func TestMappedPullRequestCopiesGlanceFields(t *testing.T) {
	var pullRequest rawPullRequest
	if err := json.Unmarshal([]byte(`{
		"number": 12,
		"title": "Ship hover",
		"url": "https://github.com/owner/one/pull/12",
		"headRefName": "GH-12",
		"headRefOid": "abcdef1",
		"baseRefName": "main",
		"isDraft": false,
		"mergeable": "MERGEABLE",
		"updatedAt": "2026-09-05T12:00:00Z",
		"additions": 40,
		"deletions": 3,
		"changedFiles": 2,
		"reviewDecision": "REVIEW_REQUIRED",
		"author": {"login": "jameson"},
		"labels": {"nodes": [{"name": "ready"}]},
		"assignees": {"nodes": [{"login": "reviewer"}]},
		"comments": {"totalCount": 4},
		"reviewRequests": {"nodes": [{"requestedReviewer": {"login": "octocat"}}]},
		"commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]}
	}`), &pullRequest); err != nil {
		t.Fatal(err)
	}
	got := mappedPullRequest("owner/one", pullRequest, 2)
	if got.AuthorLogin != "jameson" || got.BaseRefName != "main" {
		t.Fatalf("identity = %+v", got)
	}
	if got.Additions != 40 || got.Deletions != 3 || got.ChangedFiles != 2 {
		t.Fatalf("diffstat = %+v", got)
	}
	if got.CIState != "SUCCESS" || got.CommentCount != 4 {
		t.Fatalf("status = %+v", got)
	}
	if len(got.Labels) != 1 || got.Labels[0] != "ready" {
		t.Fatalf("labels = %v", got.Labels)
	}
	if len(got.ReviewRequests) != 1 || got.ReviewRequests[0] != "octocat" {
		t.Fatalf("review requests = %v", got.ReviewRequests)
	}
}
