package model

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestOptionalTimestampsOmitZeroValues(t *testing.T) {
	contents, err := json.Marshal(struct {
		Issue       Issue       `json:"issue"`
		PullRequest PullRequest `json:"pull_request"`
	}{})
	if err != nil {
		t.Fatal(err)
	}
	value := string(contents)
	for _, field := range []string{"closed_at", "merged_at"} {
		if strings.Contains(value, field) {
			t.Fatalf("zero timestamp %q was serialized: %s", field, value)
		}
	}
}
