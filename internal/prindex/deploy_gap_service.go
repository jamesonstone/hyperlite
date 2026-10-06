package prindex

import (
	"context"
	"sort"
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/model"
)

// DeployClient reads default-branch deploy history for behind pipelines.
type DeployClient interface {
	CheckDeploys(context.Context, []DeployRequest) map[string]DeployResult
}

const (
	deployRecheckInterval = 6 * time.Hour
	deployBehindRecheck   = 20 * time.Minute
	deployErrorRetry      = 15 * time.Minute
)

// refreshDeployGaps rechecks deploy history only for refreshed repositories
// whose tip or deploy runs changed since the last check, plus a slow
// periodic recheck. Most refreshes make no deploy requests at all.
func (s Scanner) refreshDeployGaps(
	ctx context.Context,
	cache cacheState,
	repositories []config.Repository,
	now time.Time,
) (cacheState, error) {
	if s.Deploys == nil || len(repositories) == 0 {
		return cache, nil
	}
	var requests []DeployRequest
	fingerprints := map[string]string{}
	cleared := map[string]bool{}
	for _, repository := range uniqueRepositories(repositories) {
		key := repositoryKey(repository.GitHub)
		activity := cache.Repositories[key].Workflows
		if activity == nil {
			continue
		}
		if !hasDeployPipeline(activity) || activity.DefaultBranch == "" {
			cleared[key] = activity.Deploys != nil
			continue
		}
		fingerprint := deployFingerprint(activity)
		if !needsDeployCheck(activity.Deploys, fingerprint, now) {
			continue
		}
		fingerprints[key] = fingerprint
		requests = append(requests, DeployRequest{Repository: repository.GitHub, DefaultBranch: activity.DefaultBranch})
	}
	var results map[string]DeployResult
	if len(requests) > 0 {
		results = s.Deploys.CheckDeploys(ctx, requests)
	}
	if len(results) == 0 && !anyTrue(cleared) {
		return cache, nil
	}
	return s.Store.Update(func(current *cacheState) bool {
		for key, wasSet := range cleared {
			if entry, found := current.Repositories[key]; found && wasSet && entry.Workflows != nil {
				entry.Workflows = cloneWorkflowActivity(entry.Workflows)
				entry.Workflows.Deploys = nil
				current.Repositories[key] = entry
			}
		}
		for key, result := range results {
			entry, found := current.Repositories[key]
			if !found || entry.Workflows == nil {
				continue
			}
			entry.Workflows = cloneWorkflowActivity(entry.Workflows)
			entry.Workflows.Deploys = appliedDeployStatus(entry.Workflows.Deploys, result, fingerprints[key], now)
			current.Repositories[key] = entry
		}
		return true
	})
}

func appliedDeployStatus(
	existing *model.DeployStatus,
	result DeployResult,
	fingerprint string,
	now time.Time,
) *model.DeployStatus {
	if result.Error != "" {
		next := cloneDeployStatus(existing)
		if next == nil {
			next = &model.DeployStatus{}
		}
		next.CheckedAt = now.UTC()
		next.Message = result.Error
		return next
	}
	return &model.DeployStatus{
		Fingerprint: fingerprint, CheckedAt: now.UTC(),
		Pipelines: result.Pipelines, PullRequests: result.PullRequests,
	}
}

func needsDeployCheck(status *model.DeployStatus, fingerprint string, now time.Time) bool {
	if status == nil {
		return true
	}
	age := now.Sub(status.CheckedAt)
	if status.Message != "" {
		return age >= deployErrorRetry
	}
	if status.Fingerprint != fingerprint {
		return true
	}
	if status.IsBehind() {
		return age >= deployBehindRecheck
	}
	return age >= deployRecheckInterval
}

func hasDeployPipeline(activity *model.ProjectWorkflowActivity) bool {
	for _, definition := range activity.Catalog {
		if ClassifyPipeline(definition.File, definition.Name) == model.PipelineAlertKindDeploy {
			return true
		}
	}
	for _, run := range activity.Runs {
		if run.Scope == model.WorkflowRunScopeTip && ClassifyPipeline(run.File, run.Name) == model.PipelineAlertKindDeploy {
			return true
		}
	}
	return false
}

// deployFingerprint changes when the default-branch tip moves or a deploy
// run on it changes state, which is when the deploy gap can change.
func deployFingerprint(activity *model.ProjectWorkflowActivity) string {
	parts := []string{activity.TipOID}
	for _, run := range activity.Runs {
		if run.Scope != model.WorkflowRunScopeTip || ClassifyPipeline(run.File, run.Name) != model.PipelineAlertKindDeploy {
			continue
		}
		parts = append(parts, strings.Join([]string{
			run.File, run.Status, run.Conclusion, run.UpdatedAt.UTC().Format(time.RFC3339),
		}, ":"))
	}
	sort.Strings(parts[1:])
	return strings.Join(parts, "|")
}

func anyTrue(values map[string]bool) bool {
	for _, value := range values {
		if value {
			return true
		}
	}
	return false
}
