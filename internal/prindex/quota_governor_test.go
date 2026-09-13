package prindex

import (
	"testing"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func governorRateLimit(remaining int, now, resetAt time.Time, pointsPerHour float64) *model.GitHubRateLimit {
	limit := &model.GitHubRateLimit{
		Limit: 5000, Used: 5000 - remaining, Remaining: remaining,
		ResetAt: resetAt, ObservedAt: now.Add(-time.Minute),
	}
	if pointsPerHour > 0 {
		limit.BurnRate = &model.GitHubRateLimitBurnRate{PointsPerHour: pointsPerHour, SampleSeconds: 120}
	}
	return limit
}

func TestDecideActivityPollReasons(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	reset := now.Add(30 * time.Minute)
	policy := defaultActivityPollPolicy
	healthy := governorRateLimit(4000, now, reset, 0)
	tests := []struct {
		name    string
		in      activityPollInput
		allowed bool
		reason  string
		next    *time.Time
	}{
		{"no active runs", activityPollInput{RateLimit: healthy, Now: now}, false, activityPollNoActiveRuns, nil},
		{"no rate limit", activityPollInput{ActiveRunCount: 1, Now: now}, false, activityPollNoRateLimit, nil},
		{
			"stale rate limit",
			activityPollInput{ActiveRunCount: 1, Now: now, RateLimit: &model.GitHubRateLimit{
				Limit: 5000, Used: 0, Remaining: 5000, ResetAt: reset, ObservedAt: now.Add(-3 * time.Hour),
			}},
			false, activityPollStaleRateLimit, nil,
		},
		{
			"quota floor at fraction",
			activityPollInput{ActiveRunCount: 1, Now: now, RateLimit: governorRateLimit(1499, now, reset, 0)},
			false, activityPollQuotaFloor, &reset,
		},
		{
			"quota floor boundary allows",
			activityPollInput{ActiveRunCount: 1, Now: now, RateLimit: governorRateLimit(1500, now, reset, 0)},
			true, activityPollOK, nil,
		},
		{
			"reserve before reset",
			// 2000 remaining, burning 2400/hr with 30 minutes left projects 800 < 1000 reserve.
			activityPollInput{ActiveRunCount: 1, Now: now, RateLimit: governorRateLimit(2000, now, reset, 2400)},
			false, activityPollQuotaReserve, &reset,
		},
		{
			"reserve boundary allows",
			// 2000 remaining, burning 2000/hr with 30 minutes left projects exactly 1000.
			activityPollInput{ActiveRunCount: 1, Now: now, RateLimit: governorRateLimit(2000, now, reset, 2000)},
			true, activityPollOK, nil,
		},
		{
			"window cap",
			activityPollInput{ActiveRunCount: 1, Now: now, RateLimit: healthy, PollsThisWindow: 60},
			false, activityPollWindowCap, &reset,
		},
		{
			"burst cap",
			activityPollInput{ActiveRunCount: 1, Now: now, RateLimit: healthy, BurstStartedAt: now.Add(-30 * time.Minute)},
			false, activityPollBurstCap, nil,
		},
		{
			"interval",
			activityPollInput{ActiveRunCount: 1, Now: now, RateLimit: healthy, LastCheckedAt: now.Add(-44 * time.Second)},
			false, activityPollInterval, timePointer(now.Add(time.Second)),
		},
		{
			"interval boundary allows",
			activityPollInput{ActiveRunCount: 1, Now: now, RateLimit: healthy, LastCheckedAt: now.Add(-45 * time.Second)},
			true, activityPollOK, nil,
		},
		{
			"reset crossed restores quota and ignores burn",
			activityPollInput{ActiveRunCount: 1, Now: reset.Add(time.Minute), RateLimit: governorRateLimit(10, now, reset, 100000)},
			true, activityPollOK, nil,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			decision := decideActivityPoll(policy, test.in)
			if decision.Allowed != test.allowed || decision.Reason != test.reason {
				t.Fatalf("decision = %v %q, want %v %q", decision.Allowed, decision.Reason, test.allowed, test.reason)
			}
			if test.allowed {
				if decision.NextEligibleAt == nil || !decision.NextEligibleAt.Equal(test.in.Now.Add(policy.Interval)) {
					t.Fatalf("next eligible = %v, want %v", decision.NextEligibleAt, test.in.Now.Add(policy.Interval))
				}
				return
			}
			switch {
			case test.next == nil && decision.NextEligibleAt != nil:
				t.Fatalf("unexpected next eligible %v", decision.NextEligibleAt)
			case test.next != nil && (decision.NextEligibleAt == nil || !decision.NextEligibleAt.Equal(*test.next)):
				t.Fatalf("next eligible = %v, want %v", decision.NextEligibleAt, test.next)
			}
		})
	}
}

func TestDecideActivityPollEchoesPolicyAndState(t *testing.T) {
	now := time.Date(2026, 9, 12, 20, 0, 0, 0, time.UTC)
	burst := now.Add(-5 * time.Minute)
	checked := now.Add(-2 * time.Minute)
	decision := decideActivityPoll(defaultActivityPollPolicy, activityPollInput{
		ActiveRunCount: 2, Now: now, PollsThisWindow: 7,
		RateLimit:      governorRateLimit(4000, now, now.Add(time.Hour), 0),
		BurstStartedAt: burst, LastCheckedAt: checked,
	})
	if !decision.Allowed || decision.ActiveRunCount != 2 || decision.PollsThisWindow != 7 ||
		decision.IntervalSeconds != 60 || decision.MaxBurstSeconds != 1800 ||
		decision.BurstStartedAt == nil || !decision.BurstStartedAt.Equal(burst) ||
		decision.LastCheckedAt == nil || !decision.LastCheckedAt.Equal(checked) {
		t.Fatalf("unexpected decision %+v", decision)
	}
}

func timePointer(value time.Time) *time.Time {
	return &value
}
