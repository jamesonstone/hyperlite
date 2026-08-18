package agentsession

import (
	"strings"
	"time"
)

const (
	ControlSchema = "agent_session_control.v1"
	HealthSchema  = "agent_integration_health.v1"
)

type ControlOperation string

const (
	ControlForegroundRefresh ControlOperation = "foreground_refresh"
	ControlManualRefresh     ControlOperation = "manual_refresh"
	ControlIntegrationTest   ControlOperation = "integration_self_test"
)

type ControlRequest struct {
	Schema    string           `json:"schema"`
	Operation ControlOperation `json:"operation"`
	Profile   string           `json:"profile,omitempty"`
	RequestID string           `json:"request_id,omitempty"`
}

func (r ControlRequest) Valid() bool {
	if r.Schema != ControlSchema {
		return false
	}
	switch r.Operation {
	case ControlForegroundRefresh, ControlManualRefresh:
		return r.Profile == "" && r.RequestID == ""
	case ControlIntegrationTest:
		_, known := ProfileByID(r.Profile)
		return known && validOpaqueRequestID(r.RequestID)
	default:
		return false
	}
}

func validOpaqueRequestID(value string) bool {
	if value == "" || len(value) > 128 {
		return false
	}
	for _, character := range value {
		if !strings.ContainsRune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_", character) {
			return false
		}
	}
	return true
}

type IntegrationHealth struct {
	Schema          string     `json:"schema"`
	Provider        string     `json:"provider"`
	Profile         string     `json:"profile"`
	Transport       string     `json:"transport"`
	ConnectionState string     `json:"connection_state"`
	LastEventAt     *time.Time `json:"last_event_at,omitempty"`
	LastAckAt       *time.Time `json:"last_acknowledgement_at,omitempty"`
	WatchersUsed    int        `json:"watchers_used"`
	WatchersLimit   int        `json:"watchers_limit"`
	FilteredCount   uint64     `json:"filtered_count"`
	RejectedCount   uint64     `json:"rejected_count"`
	SelfTestResult  string     `json:"self_test_result,omitempty"`
	ErrorCode       string     `json:"error_code,omitempty"`
}

type PhaseTransition struct {
	Timestamp time.Time `json:"timestamp"`
	Provider  string    `json:"provider"`
	SessionID string    `json:"session_id"`
	Source    Source    `json:"source"`
	OldPhase  Phase     `json:"old_phase"`
	NewPhase  Phase     `json:"new_phase"`
	Reason    string    `json:"reason"`
}

const maxPhaseTransitions = 256
