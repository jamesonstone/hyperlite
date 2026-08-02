package prindex

import (
	"encoding/json"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

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
	return value.Limit > 0 &&
		value.Used >= 0 && value.Used <= value.Limit &&
		value.Remaining >= 0 && value.Remaining <= value.Limit &&
		value.Used == value.Limit-value.Remaining &&
		!value.ResetAt.IsZero() && value.Cost >= 0 && value.NodeCount >= 0
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
	return &cloned
}

func validCachedRateLimit(value model.GitHubRateLimit) bool {
	return value.Limit > 0 &&
		value.Used >= 0 && value.Used <= value.Limit &&
		value.Remaining >= 0 && value.Remaining <= value.Limit &&
		value.Used == value.Limit-value.Remaining &&
		!value.ResetAt.IsZero() && value.Cost >= 0 && value.NodeCount >= 0 &&
		!value.ObservedAt.IsZero()
}
