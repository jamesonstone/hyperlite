package prindex

import (
	"strings"
	"time"

	"github.com/jamesonstone/hyperlite/internal/model"
)

func ClassifyPipeline(file, name string) string {
	stem := strings.ToLower(strings.TrimSuffix(strings.TrimSuffix(strings.TrimSpace(file), ".yaml"), ".yml"))
	display := strings.ToLower(strings.TrimSpace(name))
	if strings.HasPrefix(stem, "deploy") || strings.HasPrefix(display, "deploy") {
		return model.PipelineAlertKindDeploy
	}
	if stem == "main" || stem == "ci" || display == "main" || display == "ci" {
		return model.PipelineAlertKindMain
	}
	return ""
}

func isFailedConclusion(value string) bool {
	switch strings.ToUpper(strings.TrimSpace(value)) {
	case "FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE":
		return true
	}
	return false
}

func isSuccessfulConclusion(value string) bool {
	return strings.ToUpper(strings.TrimSpace(value)) == "SUCCESS"
}

func isFailedDeployment(state string) bool {
	switch strings.ToUpper(strings.TrimSpace(state)) {
	case "FAILURE", "ERROR":
		return true
	}
	return false
}

func isSuccessfulDeployment(state string) bool {
	switch strings.ToUpper(strings.TrimSpace(state)) {
	case "SUCCESS", "ACTIVE":
		return true
	}
	return false
}

func laterThanAlert(existing model.PipelineAlert, at time.Time) bool {
	if existing.Kind == "" {
		return true
	}
	return !at.IsZero() && at.After(existing.ObservedAt)
}

func matchesAlertSource(existing model.PipelineAlert, file, name string) bool {
	if existing.Kind == "" {
		return true
	}
	if strings.TrimSpace(existing.File) != "" {
		return strings.EqualFold(strings.TrimSpace(existing.File), strings.TrimSpace(file))
	}
	if strings.TrimSpace(existing.Name) != "" && ClassifyPipeline("", existing.Name) != "" {
		return strings.EqualFold(strings.TrimSpace(existing.Name), strings.TrimSpace(name))
	}
	return true
}

// ReconcilePipelineAlerts keeps cached main/deploy failures until a later
// matching tip completion is green. Pull-request runs are ignored. Missing
// or older observations keep the previous alert so a new tip SHA without
// suites, a sibling workflow success, or a stale cached run does not drop
// a still-red pipeline.
func ReconcilePipelineAlerts(
	existing []model.PipelineAlert,
	activity model.ProjectWorkflowActivity,
	now time.Time,
) []model.PipelineAlert {
	kept := map[string]model.PipelineAlert{}
	for _, alert := range existing {
		if alert.Kind == model.PipelineAlertKindMain || alert.Kind == model.PipelineAlertKindDeploy {
			kept[alert.Kind] = alert
		}
	}
	var alerts []model.PipelineAlert
	if next, keep := reconcileMainAlert(kept[model.PipelineAlertKindMain], activity, now); keep {
		alerts = append(alerts, next)
	}
	if next, keep := reconcileDeployAlert(kept[model.PipelineAlertKindDeploy], activity, now); keep {
		alerts = append(alerts, next)
	}
	return alerts
}

func reconcileMainAlert(
	existing model.PipelineAlert,
	activity model.ProjectWorkflowActivity,
	now time.Time,
) (model.PipelineAlert, bool) {
	return reconcileKindFromRuns(existing, model.PipelineAlertKindMain, activity.Runs, now)
}

func reconcileDeployAlert(
	existing model.PipelineAlert,
	activity model.ProjectWorkflowActivity,
	now time.Time,
) (model.PipelineAlert, bool) {
	next, keep := reconcileKindFromRuns(existing, model.PipelineAlertKindDeploy, activity.Runs, now)
	failedEnv, hasFailedEnv := latestFailedEnvironment(activity.Deployments)
	if hasFailedEnv && laterThanAlert(existing, failedEnv.UpdatedAt) && (!keep || failedEnv.UpdatedAt.After(next.ObservedAt)) {
		return alertFromDeployment(failedEnv, now), true
	}
	if existing.Kind == model.PipelineAlertKindDeploy && existing.File == "" {
		if hasFailedEnv {
			return next, keep
		}
		if !keep {
			return model.PipelineAlert{}, false
		}
		successEnv, hasSuccessEnv := latestSuccessfulEnvironment(activity.Deployments)
		if hasSuccessEnv && laterThanAlert(existing, successEnv.UpdatedAt) {
			return model.PipelineAlert{}, false
		}
		return next, true
	}
	if keep {
		return next, true
	}
	return model.PipelineAlert{}, false
}

func reconcileKindFromRuns(
	existing model.PipelineAlert,
	kind string,
	runs []model.WorkflowRun,
	now time.Time,
) (model.PipelineAlert, bool) {
	failed, hasFail := latestTipWhere(runs, kind, func(run model.WorkflowRun) bool {
		return isFailedConclusion(run.Conclusion)
	})
	if hasFail && laterThanAlert(existing, failed.UpdatedAt) {
		return alertFromRun(kind, failed, now), true
	}
	if existing.Kind != kind {
		return model.PipelineAlert{}, false
	}
	success, hasSuccess := latestTipWhere(runs, kind, func(run model.WorkflowRun) bool {
		return isSuccessfulConclusion(run.Conclusion) && matchesAlertSource(existing, run.File, run.Name)
	})
	if hasSuccess && laterThanAlert(existing, success.UpdatedAt) {
		return model.PipelineAlert{}, false
	}
	return existing, true
}

func latestTipWhere(runs []model.WorkflowRun, kind string, pred func(model.WorkflowRun) bool) (model.WorkflowRun, bool) {
	var latest model.WorkflowRun
	found := false
	for _, run := range runs {
		if run.Scope != model.WorkflowRunScopeTip || run.IsActive() {
			continue
		}
		if ClassifyPipeline(run.File, run.Name) != kind {
			continue
		}
		if !pred(run) {
			continue
		}
		if !found || run.UpdatedAt.After(latest.UpdatedAt) {
			latest = run
			found = true
		}
	}
	return latest, found
}

func latestFailedEnvironment(deployments []model.Deployment) (model.Deployment, bool) {
	latest := map[string]model.Deployment{}
	for _, deployment := range deployments {
		if deployment.IsActive() {
			continue
		}
		if existing, found := latest[deployment.Environment]; found && !deployment.UpdatedAt.After(existing.UpdatedAt) {
			continue
		}
		latest[deployment.Environment] = deployment
	}
	var failed model.Deployment
	found := false
	for _, deployment := range latest {
		if !isFailedDeployment(deployment.State) {
			continue
		}
		if !found || deployment.UpdatedAt.After(failed.UpdatedAt) {
			failed = deployment
			found = true
		}
	}
	return failed, found
}

func latestSuccessfulEnvironment(deployments []model.Deployment) (model.Deployment, bool) {
	var latest model.Deployment
	found := false
	for _, deployment := range deployments {
		if deployment.IsActive() || !isSuccessfulDeployment(deployment.State) {
			continue
		}
		if !found || deployment.UpdatedAt.After(latest.UpdatedAt) {
			latest = deployment
			found = true
		}
	}
	return latest, found
}

func alertFromRun(kind string, run model.WorkflowRun, now time.Time) model.PipelineAlert {
	observed := run.UpdatedAt.UTC()
	if observed.IsZero() {
		observed = now.UTC()
	}
	name := strings.TrimSpace(run.Name)
	if name == "" {
		name = kind
	}
	return model.PipelineAlert{
		Kind: kind, File: run.File, Name: name, Conclusion: run.Conclusion,
		URL: run.URL, RunNumber: run.RunNumber, HeadOID: run.HeadOID,
		ObservedAt: observed,
	}
}

func alertFromDeployment(deployment model.Deployment, now time.Time) model.PipelineAlert {
	observed := deployment.UpdatedAt.UTC()
	if observed.IsZero() {
		observed = now.UTC()
	}
	name := strings.TrimSpace(deployment.Environment)
	if name == "" {
		name = model.PipelineAlertKindDeploy
	}
	return model.PipelineAlert{
		Kind: model.PipelineAlertKindDeploy, Name: name, Conclusion: deployment.State,
		URL: deployment.LogURL, ObservedAt: observed,
	}
}
