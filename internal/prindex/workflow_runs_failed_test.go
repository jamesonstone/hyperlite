package prindex

import (
	"encoding/json"
	"testing"
)

func TestFailingAndPendingHeadsGetRunFollowUp(t *testing.T) {
	var raw rawRepository
	body := `{"pullRequests":{"nodes":[
		{"number":1,"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},
		{"number":2,"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}},
		{"number":3,"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING"}}}]}},
		{"number":4,"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"ERROR"}}}]}}
	]}}`
	if err := json.Unmarshal([]byte(body), &raw); err != nil {
		t.Fatal(err)
	}
	activity := repositoryActivityFromRaw(nil, &raw, "owner/one")
	if got := activity.PendingHeads; len(got) != 3 || got[0] != 1 || got[1] != 3 || got[2] != 4 {
		t.Fatalf("heads = %v, want failing and pending only", got)
	}
}
