---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0035"
  slug: open-pr-pipeline-alerts
  dir: 0035-open-pr-pipeline-alerts
references:
  - id: issue-106
    name: Persist main and deploy pipeline failure indicators in Open PRs
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/106
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-workflow-activity
    name: Open PR Workflow Activity
    type: specification
    target: docs/specs/0031-open-pr-workflow-activity/SPEC.md
    relation: constrains
    read_policy: must
    used_for: existing default-branch check suites, deployments, activity poll, and quota governor
    status: active
  - id: open-pr-watch-stage
    name: Open PR Watch Stage
    type: specification
    target: docs/specs/0033-open-pr-watch-stage/SPEC.md
    relation: constrains
    read_policy: must
    used_for: lantern stages and hide-idle notable membership
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Open PR panel presentation
    status: active
  - id: backend-architecture
    name: Backend Service Architecture
    type: ruleset
    target: docs/references/rules/backend-service-architecture.md
    relation: constrains
    read_policy: must
    used_for: prindex cache reconcile without a new GitHub client
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Go and Swift gates
    status: active
skills: []
---

# Open PR Pipeline Alerts

## PURPOSE

Show a persistent, project-level signal when a watched repository's
default-branch **main** or **deploy** pipeline last failed, and drop that
signal only when the next matching pipeline run is green, without adding
GitHub traffic.

## CONTEXT

Open PRs already fetches default-branch GitHub Actions check suites and the
last five deployments on the bounded pull-request batch and the quota-governed
`--activity` poll (0031). Workflow chips currently pick the newest run of a
file across every scope, so a later pull-request CI run can hide a failed
`main` or `deploy` tip run, and a new tip SHA with no suite yet can drop the
failure entirely.

The operator needs those two pipelines to stay red until they pass. Extra
`gh` or GraphQL calls would fight the Constitution's quota governor.

Orchestration: single-lane, because classification, additive cache fields,
JSON decoding, heading badges, lantern color, and hide-idle membership share
one presentation contract and need continuous design judgment.

## REQUIREMENTS

- R1: Each project may show at most two persistent pipeline badges: **main**
  (workflow file/name `main` or `ci`) and **deploy** (`deploy*` workflow or a
  failed environment deployment). Badges stay on the heading until cleared.
- R2: A badge is set from a completed default-branch (`tip`) failure
  (`FAILURE`, `TIMED_OUT`, `ACTION_REQUIRED`, `STARTUP_FAILURE`) or a finished
  environment deployment in `FAILURE`/`ERROR`. A later matching tip success of
  the same workflow file (or name when no file is stored), or a later finished
  non-failed deployment with no remaining failed environments, clears that kind.
  A successful `ci` run does not clear a stored `main.yaml` failure. An older
  terminal observation does not clear or replace a newer cached alert.
  Environment success without a matching deploy workflow completion does not
  clear a workflow-sourced deploy alert. An in-progress run does not clear a
  stored failure.
- R3: Pull-request-scoped runs never set or clear these badges. A scan or poll
  that does not observe a newer matching completion keeps the cached alert.
  A failed GitHub activity poll does not rewrite alerts.
- R4: Do not add GraphQL selections, REST endpoints, webhooks, or a per-repo
  `gh` process. Alerts are reconciled locally from activity already fetched.
  The activity poll and quota governor are unchanged.
- R5: A project with a pipeline alert stays visible under hide-idle. Its
  lantern is orange when nothing is running; a live running chip still lights
  cyan. Clicking a badge opens the failed run or deployment log.
- R6: Additive JSON/cache fields; legacy activity without `pipeline_alerts`
  decodes. Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Re-running, cancelling, or notifying about workflows.
- Tracking CodeQL or other non-main/non-deploy workflows as pipeline alerts.
- Changing poll cadence, burst length, or governor thresholds.

Observable acceptance:

- A failed default-branch `main`/`ci` or `deploy` run shows a heading badge
  that survives a later pull-request CI run and a tip SHA with no new suite.
- The next matching green tip run or successful deploy removes that badge.
- Batch and `--activity` query-shape tests still forbid extra connections.

## ACCEPTED PLAN

1. Add an additive `pipeline_alerts` field on cached workflow activity and a
   pure reconcile that classifies tip runs and deployments into `main`/`deploy`.
2. Call that reconcile after a successful full refresh and after a successful
   activity poll merge; never on a poll error.
3. Decode alerts natively and render persistent heading badges with run/log
   links; orange lantern when alerts exist and nothing is running.
4. Fold alerts into hide-idle notable membership and heading weight.
5. Cover classify/reconcile, cache round-trip, unchanged query shape, decode,
   badge membership, and hide-idle with tests.

## DECISIONS

- `ci` is treated as the default-branch **main** pipeline because watched
  repositories often name that workflow `ci.yaml` rather than `main.yaml`.
- Alerts are repository cache state, not a new GitHub resource. Persistence
  is "keep until a newer matching completion is green," not a history query.
- Environment `FAILURE`/`ERROR` counts as **deploy** even when no `deploy*`
  workflow file exists, matching 0031's environment coverage.
- Pull-request CI stays on the existing chip strip; pipeline badges are a
  separate, higher-priority heading signal so they cannot be crowded out.

## DISCOVERIES

- `latestRun` prefers any active run, then the newest created run of a file,
  including `pull_request` scope. That is why a failed tip `main` disappeared
  after a newer PR CI observation.
- Default-branch suites are only those on the current tip commit. Caching the
  last failed completion is required to survive a fast-forward that has not
  run yet.
- `main` and `ci` share the **main** badge, but they are distinct workflow
  sources. Grouping them only as a kind let a later `ci.yml` success clear an
  unresolved `main.yaml` failure.
- The Actions cache can return an older completed suite or deployment than the
  cached alert. Reconcile must compare `UpdatedAt` with `ObservedAt` so an
  older terminal observation cannot clear or replace a newer failure.

## VALIDATION

- `make fmt-check vet test test-race` PASS. Go coverage includes pipeline
  classification, tip-failure persistence across pull-request success and
  missing observations, in-progress tip not clearing, matching-file green tip
  clearing, `ci` success not clearing `main.yaml`, older terminal observations
  not clearing or replacing a newer cached alert, failed deploy workflow and
  environment sources, environment success not clearing a workflow-sourced
  deploy alert, cache round-trip of `pipeline_alerts`, and unchanged
  batch/`--activity` query shape.
- `make macos-test macos-build` PASS. Swift coverage includes legacy decode
  without `pipeline_alerts`, heading badge membership, hide-idle notable
  membership, and orange alert lantern vs cyan running lantern.

## OUTCOME

Open PRs project headings show persistent **main** and **deploy** badges when
those default-branch pipelines last failed. A later pull-request CI run does
not clear them. The next matching green tip run or successful deploy does.
Nothing new is fetched from GitHub; alerts are reconciled from the existing
Actions cache. Hide-idle keeps alerted projects visible.

## REPOSITORY MEMORY

- Decision: created
- Rationale: persistence rules, `ci`≡main, environment failures as deploy,
  and the no-new-GitHub-call constraint are product decisions that code and tests
  cannot preserve alone.
- Artifacts: `docs/specs/0035-open-pr-pipeline-alerts/SPEC.md`,
  `docs/USER_GUIDE.md`, `docs/references/testing.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`
