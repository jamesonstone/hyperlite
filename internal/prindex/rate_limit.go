package prindex

import (
	"encoding/json"
	"math"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

const minimumBurnRateSample = time.Minute

type GitHubRateLimit struct {
	Limit     int
	Used      int
	Remaining int
	ResetAt   time.Time
	Cost      int
	NodeCount int
}

type ClientResult struct {
	Repositories map[string]RepositoryResult
	RateLimit    *GitHubRateLimit
}

type rawRateLimit struct {
	Limit     int       `json:"limit"`
	Used      int       `json:"used"`
	Remaining int       `json:"remaining"`
	ResetAt   time.Time `json:"resetAt"`
	Cost      int       `json:"cost"`
	NodeCount int       `json:"nodeCount"`
}

type rateLimitFields struct {
	Limit     int
	Used      int
	Remaining int
	ResetAt   time.Time
	Cost      int
	NodeCount int
}

type rateLimitCollector struct {
	latest *GitHubRateLimit
}

func (c *rateLimitCollector) observe(data map[string]json.RawMessage) {
	value, found := data["rateLimit"]
	if !found {
		return
	}
	var raw rawRateLimit
	if err := json.Unmarshal(value, &raw); err != nil || !validRawRateLimit(raw) {
		return
	}
	c.latest = &GitHubRateLimit{
		Limit: raw.Limit, Used: raw.Used, Remaining: raw.Remaining,
		ResetAt: raw.ResetAt.UTC(), Cost: raw.Cost, NodeCount: raw.NodeCount,
	}
}

func validRawRateLimit(value rawRateLimit) bool {
	return validRateLimitFields(rateLimitFields{
		Limit: value.Limit, Used: value.Used, Remaining: value.Remaining,
		ResetAt: value.ResetAt, Cost: value.Cost, NodeCount: value.NodeCount,
	})
}

func observedRateLimit(value *GitHubRateLimit, observedAt time.Time) *model.GitHubRateLimit {
	if value == nil {
		return nil
	}
	return &model.GitHubRateLimit{
		Limit: value.Limit, Used: value.Used, Remaining: value.Remaining,
		ResetAt: value.ResetAt.UTC(), Cost: value.Cost, NodeCount: value.NodeCount,
		ObservedAt: observedAt.UTC(),
	}
}

func cloneRateLimit(value *model.GitHubRateLimit) *model.GitHubRateLimit {
	if value == nil {
		return nil
	}
	cloned := *value
	if value.BurnRate != nil {
		burnRate := *value.BurnRate
		if value.BurnRate.ProjectedExhaustionAt != nil {
			projected := *value.BurnRate.ProjectedExhaustionAt
			burnRate.ProjectedExhaustionAt = &projected
		}
		cloned.BurnRate = &burnRate
	}
	return &cloned
}

func deriveRateLimitBurnRate(
	current *model.GitHubRateLimit,
	previous *model.GitHubRateLimit,
) *model.GitHubRateLimit {
	if current == nil || previous == nil ||
		current.Limit != previous.Limit ||
		!current.ResetAt.Equal(previous.ResetAt) ||
		!current.ResetAt.After(current.ObservedAt) ||
		!previous.ResetAt.After(previous.ObservedAt) ||
		current.Used < previous.Used {
		return current
	}
	elapsed := current.ObservedAt.Sub(previous.ObservedAt)
	if elapsed < minimumBurnRateSample {
		return current
	}
	pointsPerHour := float64(current.Used-previous.Used) / elapsed.Hours()
	if math.IsNaN(pointsPerHour) || math.IsInf(pointsPerHour, 0) || pointsPerHour < 0 {
		return current
	}
	burnRate := &model.GitHubRateLimitBurnRate{
		PointsPerHour: pointsPerHour,
		SampleSeconds: int64(elapsed / time.Second),
	}
	if pointsPerHour > 0 {
		projected, valid := projectedRateLimitExhaustion(
			current.ObservedAt, current.Remaining, pointsPerHour,
		)
		if !valid {
			return current
		}
		burnRate.ProjectedExhaustionAt = &projected
	}
	current.BurnRate = burnRate
	return current
}

func validCachedRateLimit(value model.GitHubRateLimit) bool {
	return validRateLimitFields(rateLimitFields{
		Limit: value.Limit, Used: value.Used, Remaining: value.Remaining,
		ResetAt: value.ResetAt, Cost: value.Cost, NodeCount: value.NodeCount,
	}) && !value.ObservedAt.IsZero() && validCachedBurnRate(value)
}

func validCachedBurnRate(value model.GitHubRateLimit) bool {
	burnRate := value.BurnRate
	if burnRate == nil {
		return true
	}
	if math.IsNaN(burnRate.PointsPerHour) || math.IsInf(burnRate.PointsPerHour, 0) ||
		burnRate.PointsPerHour < 0 || burnRate.SampleSeconds <
		int64(minimumBurnRateSample/time.Second) {
		return false
	}
	if burnRate.PointsPerHour == 0 {
		return burnRate.ProjectedExhaustionAt == nil
	}
	if burnRate.ProjectedExhaustionAt == nil {
		return false
	}
	expected, valid := projectedRateLimitExhaustion(
		value.ObservedAt, value.Remaining, burnRate.PointsPerHour,
	)
	return valid && math.Abs(
		burnRate.ProjectedExhaustionAt.Sub(expected).Seconds(),
	) <= 1
}

func projectedRateLimitExhaustion(
	observedAt time.Time,
	remaining int,
	pointsPerHour float64,
) (time.Time, bool) {
	seconds := float64(remaining) / pointsPerHour * 3600
	if math.IsNaN(seconds) || math.IsInf(seconds, 0) || seconds < 0 ||
		seconds > float64(math.MaxInt64)/float64(time.Second) {
		return time.Time{}, false
	}
	return observedAt.Add(time.Duration(seconds * float64(time.Second))), true
}

func validRateLimitFields(value rateLimitFields) bool {
	return value.Limit > 0 &&
		value.Used >= 0 && value.Used <= value.Limit &&
		value.Remaining >= 0 && value.Remaining <= value.Limit &&
		value.Used == value.Limit-value.Remaining &&
		!value.ResetAt.IsZero() && value.Cost >= 0 && value.NodeCount >= 0
}
