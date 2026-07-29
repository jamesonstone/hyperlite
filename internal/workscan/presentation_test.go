package workscan

import (
	"testing"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func TestFinalizeScanIsIdempotent(t *testing.T) {
	result := model.ThreadScan{Threads: []model.Thread{
		{
			ID: "active", Active: true,
			Attention: []model.AttentionMoment{{ID: "moment", Seen: false}},
		},
		{ID: "complete", Active: false},
	}}
	finalizeScan(&result)
	first := result.Summary
	finalizeScan(&result)
	if result.Summary != first ||
		result.Summary.Attention != 1 ||
		result.Summary.InFlight != 1 ||
		result.Summary.Completed != 1 {
		t.Fatalf("summary = %#v, first = %#v", result.Summary, first)
	}
}
