package prindex

import (
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

// activityPollPolicy bounds the automatic follow-up poll that keeps running
// workflow state fresh. Explicit Refresh never consults it.
type activityPollPolicy struct {
	MinRemainingFloor    int
	MinRemainingFraction float64
	ReserveFraction      float64
	MinInterval          time.Duration
	Interval             time.Duration
	MaxBurst             time.Duration
	MaxPollsPerWindow    int
}

var defaultActivityPollPolicy = activityPollPolicy{
	MinRemainingFloor:    1000,
	MinRemainingFraction: 0.30,
	ReserveFraction:      0.20,
	MinInterval:          45 * time.Second,
	Interval:             time.Minute,
	MaxBurst:             30 * time.Minute,
	MaxPollsPerWindow:    60,
}

const (
	activityPollOK             = "ok"
	activityPollNoActiveRuns   = "no_active_runs"
	activityPollNoRateLimit    = "no_rate_limit_observation"
	activityPollQuotaFloor     = "quota_floor"
	activityPollQuotaReserve   = "quota_reserve_before_reset"
	activityPollWindowCap      = "window_cap"
	activityPollBurstCap       = "burst_cap"
	activityPollInterval       = "interval"
	activityPollStaleRateLimit = "stale_rate_limit_observation"
)

// maxRateLimitObservationAge bounds how old a quota observation may be before
// it is too unreliable to authorize automatic polling.
const maxRateLimitObservationAge = 2 * time.Hour

type activityPollInput struct {
	RateLimit       *model.GitHubRateLimit
	LastCheckedAt   time.Time
	BurstStartedAt  time.Time
	PollsThisWindow int
	ActiveRunCount  int
	Now             time.Time
}

func decideActivityPoll(policy activityPollPolicy, in activityPollInput) model.ActivityPollDecision {
	decision := model.ActivityPollDecision{
		Reason:          activityPollOK,
		ActiveRunCount:  in.ActiveRunCount,
		IntervalSeconds: int64(policy.Interval / time.Second),
		MaxBurstSeconds: int64(policy.MaxBurst / time.Second),
		BurstStartedAt:  optionalTime(in.BurstStartedAt),
		LastCheckedAt:   optionalTime(in.LastCheckedAt),
		PollsThisWindow: in.PollsThisWindow,
	}
	deny := func(reason string, next time.Time) model.ActivityPollDecision {
		decision.Allowed = false
		decision.Reason = reason
		decision.NextEligibleAt = optionalTime(next)
		return decision
	}
	if in.ActiveRunCount <= 0 {
		return deny(activityPollNoActiveRuns, time.Time{})
	}
	limit := in.RateLimit
	if limit == nil {
		return deny(activityPollNoRateLimit, time.Time{})
	}
	if in.Now.Sub(limit.ObservedAt) > maxRateLimitObservationAge {
		return deny(activityPollStaleRateLimit, time.Time{})
	}
	remaining := limit.Remaining
	windowOpen := in.Now.Before(limit.ResetAt)
	if !windowOpen {
		remaining = limit.Limit
	}
	floor := max(policy.MinRemainingFloor, int(policy.MinRemainingFraction*float64(limit.Limit)))
	if remaining < floor {
		return deny(activityPollQuotaFloor, limit.ResetAt)
	}
	reserve := policy.ReserveFraction * float64(limit.Limit)
	if windowOpen && limit.BurnRate != nil && limit.BurnRate.PointsPerHour > 0 {
		hoursUntilReset := limit.ResetAt.Sub(in.Now).Hours()
		projected := float64(remaining) - limit.BurnRate.PointsPerHour*hoursUntilReset
		if projected < reserve {
			return deny(activityPollQuotaReserve, limit.ResetAt)
		}
	}
	if windowOpen && in.PollsThisWindow >= policy.MaxPollsPerWindow {
		return deny(activityPollWindowCap, limit.ResetAt)
	}
	if !in.BurstStartedAt.IsZero() && in.Now.Sub(in.BurstStartedAt) >= policy.MaxBurst {
		return deny(activityPollBurstCap, time.Time{})
	}
	if !in.LastCheckedAt.IsZero() && in.Now.Sub(in.LastCheckedAt) < policy.MinInterval {
		return deny(activityPollInterval, in.LastCheckedAt.Add(policy.MinInterval))
	}
	decision.Allowed = true
	decision.NextEligibleAt = optionalTime(in.Now.Add(policy.Interval))
	return decision
}

func optionalTime(value time.Time) *time.Time {
	if value.IsZero() {
		return nil
	}
	utc := value.UTC()
	return &utc
}
