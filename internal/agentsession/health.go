package agentsession

import (
	"reflect"
	"strings"
	"time"
)

type HealthState struct {
	values map[string]IntegrationHealth
}

func NewHealthState(integrations []IntegrationStatus) *HealthState {
	state := &HealthState{values: make(map[string]IntegrationHealth, len(integrations))}
	for _, integration := range integrations {
		state.values[integration.ID] = IntegrationHealth{
			Schema: HealthSchema, Provider: integration.Provider, Profile: integration.ID,
			Transport: healthTransport(integration.ID), ConnectionState: "idle",
			WatchersLimit: watcherLimit(integration.ID),
		}
	}
	return state
}

func (s *HealthState) All() []IntegrationHealth {
	result := make([]IntegrationHealth, 0, len(s.values))
	for _, profile := range Profiles() {
		if value, ok := s.values[profile.ID]; ok {
			result = append(result, value)
		}
	}
	return result
}

func (s *HealthState) Event(event Event) (IntegrationHealth, bool) {
	profile := firstNonempty(event.Profile, event.Provider)
	return s.update(profile, func(value *IntegrationHealth) {
		observed := event.OccurredAt
		value.LastEventAt = &observed
		value.ConnectionState = "connected"
		value.ErrorCode = ""
	})
}

func (s *HealthState) Connection(profile, state, code string) (IntegrationHealth, bool) {
	return s.update(profile, func(value *IntegrationHealth) {
		value.ConnectionState = boundedHealthValue(state, "idle")
		value.ErrorCode = boundedHealthValue(code, "")
	})
}

func (s *HealthState) Acknowledge(profile string, now time.Time) (IntegrationHealth, bool) {
	return s.update(profile, func(value *IntegrationHealth) { value.LastAckAt = &now })
}

func (s *HealthState) Watchers(used int) (IntegrationHealth, bool) {
	return s.update("codex", func(value *IntegrationHealth) {
		value.WatchersUsed = max(0, min(used, maxCodexRolloutWatches))
	})
}

func (s *HealthState) Filtered(profile string, count uint64) (IntegrationHealth, bool) {
	return s.update(profile, func(value *IntegrationHealth) { value.FilteredCount += count })
}

func (s *HealthState) Rejected(profile, code string) (IntegrationHealth, bool) {
	return s.update(profile, func(value *IntegrationHealth) {
		value.RejectedCount++
		value.ErrorCode = boundedHealthValue(code, "rejected_event")
	})
}

func (s *HealthState) SelfTest(profile, result, code string, now time.Time) (IntegrationHealth, bool) {
	return s.update(profile, func(value *IntegrationHealth) {
		value.SelfTestResult = boundedHealthValue(result, "failed")
		value.ErrorCode = boundedHealthValue(code, "")
		value.LastAckAt = &now
	})
}

func (s *HealthState) update(profile string, mutate func(*IntegrationHealth)) (IntegrationHealth, bool) {
	value, ok := s.values[profile]
	if !ok {
		registered, found := ProfileByID(profile)
		if !found {
			return IntegrationHealth{}, false
		}
		value = IntegrationHealth{Schema: HealthSchema, Provider: registered.Provider,
			Profile: profile, Transport: healthTransport(profile), ConnectionState: "idle",
			WatchersLimit: watcherLimit(profile)}
	}
	before := value
	mutate(&value)
	if reflect.DeepEqual(before, value) {
		return value, false
	}
	s.values[profile] = value
	return value, true
}

func healthTransport(profile string) string {
	if profile == "codex" {
		return "hook+app_server+rollout"
	}
	return "hook"
}

func watcherLimit(profile string) int {
	if profile == "codex" {
		return maxCodexRolloutWatches
	}
	return 0
}

func boundedHealthValue(value, fallback string) string {
	value = firstNonempty(value, fallback)
	value = strings.ToLower(value)
	if len(value) > 64 {
		value = value[:64]
	}
	return value
}
