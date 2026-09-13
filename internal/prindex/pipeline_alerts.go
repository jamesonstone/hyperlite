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

// ReconcilePipelineAlerts keeps cached main/deploy failures until a newer
// matching tip completion is green. Pull-request runs are ignored. Missing
// observations keep the previous alert so a new tip SHA without suites does
// not drop a still-red pipeline.
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
	run, ok := latestCompletedTip(activity.Runs, model.PipelineAlertKindMain)
	if !ok {
		return existing, existing.Kind == model.PipelineAlertKindMain
	}
	if isFailedConclusion(run.Conclusion) {
		return alertFromRun(model.PipelineAlertKindMain, run, now), true
	}
	if isSuccessfulConclusion(run.Conclusion) {
		return model.PipelineAlert{}, false
	}
	return existing, existing.Kind == model.PipelineAlertKindMain
}

func reconcileDeployAlert(
	existing model.PipelineAlert,
	activity model.ProjectWorkflowActivity,
	now time.Time,
) (model.PipelineAlert, bool) {
	run, hasRun := latestCompletedTip(activity.Runs, model.PipelineAlertKindDeploy)
	failedEnv, hasFailedEnv := latestFailedEnvironment(activity.Deployments)
	if hasFailedEnv {
		return alertFromDeployment(failedEnv, now), true
	}
	if hasRun && isFailedConclusion(run.Conclusion) {
		return alertFromRun(model.PipelineAlertKindDeploy, run, now), true
	}
	if hasRun && isSuccessfulConclusion(run.Conclusion) {
		return model.PipelineAlert{}, false
	}
	if hasSuccessfulEnvironment(activity.Deployments) && !hasRun {
		return model.PipelineAlert{}, false
	}
	return existing, existing.Kind == model.PipelineAlertKindDeploy
}

func latestCompletedTip(runs []model.WorkflowRun, kind string) (model.WorkflowRun, bool) {
	var latest model.WorkflowRun
	found := false
	for _, run := range runs {
		if run.Scope != model.WorkflowRunScopeTip || run.IsActive() {
			continue
		}
		if ClassifyPipeline(run.File, run.Name) != kind {
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

func hasSuccessfulEnvironment(deployments []model.Deployment) bool {
	for _, deployment := range deployments {
		if !deployment.IsActive() && isSuccessfulDeployment(deployment.State) {
			return true
		}
	}
	return false
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
