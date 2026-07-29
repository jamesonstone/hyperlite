package workscan

import (
	"sort"

	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/jamesonstone/hyperlite/internal/model"
)

func discoveryWarnings(warnings []discovery.Warning) []model.ScanError {
	result := make([]model.ScanError, 0, len(warnings))
	for _, warning := range warnings {
		result = append(result, model.ScanError{
			Stage: "discovery-" + warning.Stage, Message: warning.Path + ": " + warning.Message,
		})
	}
	return result
}

func finalizeScan(result *model.ThreadScan) {
	sort.Slice(result.Threads, func(i, j int) bool {
		leftAttention, rightAttention := unseen(result.Threads[i]), unseen(result.Threads[j])
		if leftAttention != rightAttention {
			return leftAttention
		}
		if result.Threads[i].Active != result.Threads[j].Active {
			return result.Threads[i].Active
		}
		if !result.Threads[i].UpdatedAt.Equal(result.Threads[j].UpdatedAt) {
			return result.Threads[i].UpdatedAt.After(result.Threads[j].UpdatedAt)
		}
		return result.Threads[i].ID < result.Threads[j].ID
	})
	sortDiagnostics(result.Errors)
	sortDiagnostics(result.Warnings)
	result.Summary.Threads = len(result.Threads)
	result.Summary.Attention = 0
	result.Summary.InFlight = 0
	result.Summary.Completed = 0
	for _, thread := range result.Threads {
		if unseen(thread) {
			result.Summary.Attention++
		}
		if thread.Active {
			result.Summary.InFlight++
		} else {
			result.Summary.Completed++
		}
	}
	result.Summary.Errors = len(result.Errors)
	result.Summary.Warnings = len(result.Warnings)
}

func unseen(thread model.Thread) bool {
	for _, moment := range thread.Attention {
		if !moment.Seen {
			return true
		}
	}
	return false
}

func sortDiagnostics(diagnostics []model.ScanError) {
	sort.Slice(diagnostics, func(left, right int) bool {
		if diagnostics[left].Repository != diagnostics[right].Repository {
			return diagnostics[left].Repository < diagnostics[right].Repository
		}
		if diagnostics[left].Stage != diagnostics[right].Stage {
			return diagnostics[left].Stage < diagnostics[right].Stage
		}
		return diagnostics[left].Message < diagnostics[right].Message
	})
}
