---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0031"
  slug: open-pr-workflow-activity
  dir: 0031-open-pr-workflow-activity
references:
  - id: issue-96
    name: Show running GitHub Actions workflows and deployments per project in Open PRs
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/96
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pull-requests
    name: Configured Project Pull Requests
    type: specification
    target: docs/specs/0004-open-pull-requests/SPEC.md
    relation: constrains
    read_policy: must
    used_for: bounded GraphQL batches, cache ownership, no gh process per repository
    status: active
  - id: open-pr-project-sections
    name: Open PR Project Sections
    type: specification
    target: docs/specs/0027-open-pr-project-sections/SPEC.md
    relation: supersedes
    read_policy: must
    used_for: every configured project now owns a section; availability rows move inside it
    status: active
  - id: open-pr-refresh-ghost-overlay
    name: Open PR Refresh Ghost Overlay
    type: specification
    target: docs/specs/0030-open-pr-refresh-ghost-overlay/SPEC.md
    relation: constrains
    read_policy: must
    used_for: low-tick wall-clock animation pattern; idle has no TimelineView
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: pure presentation, state in HyperliteState
    status: active
  - id: backend-architecture
    name: Backend Service Architecture
    type: ruleset
    target: docs/references/rules/backend-service-architecture.md
    relation: constrains
    read_policy: must
    used_for: client, service, cache boundaries in prindex
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Go and Swift gates plus isolated-cache live validation
    status: active
skills: []
---

# Open PR Workflow Activity

## PURPOSE

Show, for every configured project, which GitHub Actions workflow or
environment deployment is running right now, list the project's workflows
with the running one highlighted by a gliding ghost, and link each project to
its GitHub Pulls and Actions pages, without ever exhausting or noticeably
taxing the GitHub GraphQL quota.

## CONTEXT

Deployments in the watched repositories take three to nine minutes and start
right after a merge, exactly when the merged pull request leaves Open PRs.
Hyperlite refreshed only at launch, on foreground after five minutes, or on
explicit Refresh, so a deploy indicator driven by that cadence would usually
be missing or stale. The Constitution forbade any continuous timer.

Live probes established the data shape: GraphQL has no workflow list on
`Repository`; runs are reachable through `checkSuites(filterBy: {appId:
15368})` on a commit, environment deployments through `Repository.deployments`,
and the workflow catalog through the `.github/workflows` tree on the default
branch. Seven of the twenty-three watched repositories use environments; six
others run `deploy*` workflows without environments, so default-branch tip
runs are the signal there.

Orchestration: single-lane, because the Go JSON contract and the Swift
decoders and presentation were revised together, the 300-line splits needed
continuous judgment, and the panel restructure touched the same files as the
strip and buttons.

## REQUIREMENTS

- R1: Every configured project gets an Open PRs section with its repository
  name, row count, workflow strip, and two trailing icon buttons that open
  `https://github.com/<owner>/<repo>/pulls` and `/actions`. Projects with no
  open pull requests render one quiet idle line; cached or unavailable
  projects render their availability text on that line.
- R2: The workflow strip lists every workflow file under `.github/workflows`
  on the default branch in tree order, titled by the file's top-level `name:`
  or the file name, followed by any observed run whose workflow is not a file
  (dynamic workflows such as CodeQL).
- R3: A chip whose latest run is queued, in progress, waiting, pending, or
  requested, or whose repository has an active environment deployment, is the
  running chip. Only an observation younger than two minutes may animate it;
  older active data shows a quiet `last seen HH:mm` state. Completed chips
  show a small success, failure, or cancelled mark; idle chips stay muted.
- R4: The running chip shows a thin track with a small ghost gliding back and
  forth on twelve-hertz wall-clock ticks and the elapsed run time. No
  `TimelineView` exists while nothing is running or fresh.
- R5: Hovering a chip shows a themed card with status, trigger (event, pull
  request or branch, run number), deployment environment, and links to the
  run and deployment log.
- R6: The existing bounded pull-request batch gains only repository-level
  selections: default-branch tip Actions check suites, the last five
  deployments, and the workflows tree OID. Head runs for pull requests whose
  status rollup is pending come from one small follow-up query. Workflow
  files are read only when the tree OID changed since the cached catalog.
- R7: A `pull-requests --activity` mode issues one minimal query for
  repositories with active runs and their active pull-request heads. It never
  lists pull requests or reads workflow files, and a denied governor decision
  touches neither GitHub nor the cache.
- R8: A pure quota governor decides automatic polls from the cached quota
  observation: at least the larger of 1,000 points or thirty percent of the
  limit remaining, a projected twenty percent still remaining at reset given
  the trailing burn rate, at most sixty polls per reset window, at most thirty
  minutes after the burst started, and at least forty-five seconds since the
  last poll. Every scan reports the decision in `activity_policy`.
- R9: The native app polls only while a scan reports active runs, the window
  is visible, the governor allows, and a full refresh is not in flight,
  waiting at least sixty seconds between polls and stopping after thirty
  minutes per burst. Explicit Refresh cancels and supersedes the loop.
- R10: JSON and cache changes are additive; legacy caches and JSON without the
  new fields decode, and a legacy entry hydrates once inside the five-minute
  floor like earlier projection fields.
- R11: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- REST calls, webhooks, one `gh` process per repository, re-running or
  cancelling workflows, notifications, or any GitHub mutation.
- Per-pull-request run details for pull requests whose checks already
  finished; those show only through the existing rollup state.
- Persisting drag order for sections without rows.

Observable acceptance:

- A running `ci` or `deploy` workflow appears on its project section as a
  cyan chip with a gliding ghost and elapsed time; other workflows stay quiet.
- Pulls and Actions buttons open the correct GitHub pages for the project.
- A full refresh costs about one point more than before this feature; each
  activity poll costs one point and stops when nothing is running.
- Legacy cache files and JSON still decode.

## ACCEPTED PLAN

1. Add workflow activity and poll-decision models, additive cache fields, and
   the pure quota governor in Go.
2. Extend the batch query with repository-level selections; add follow-up
   queries for changed workflow catalogs, pending pull-request heads, and the
   activity poll.
3. Add the `activity` refresh mode, catalog reconciliation on tree OID change,
   burst bookkeeping, and policy emission to the scanner and CLI.
4. Decode the new fields natively, give every configured project a section
   with buttons and a workflow strip, and add the gliding-ghost running chip
   and hover card.
5. Add the pure poll schedule and the bounded native poll loop with window
   visibility, refresh, and burst gating.
6. Cover both layers with executable tests, validate live against an isolated
   cache, amend the Constitution, and curate docs.

## DECISIONS

- Workflow file name is the join key between catalog and runs because
  `WorkflowRun.workflow.resourcePath` ends with it and display names can
  collide; dynamic workflows use their last path segment.
- Per-pull-request head check suites stay out of the batch. GitHub prices a
  nested connection by the pull-request page size, so selecting them inside
  `pullRequests(first: 100)` added roughly 47 points per refresh. Pending
  heads are fetched afterwards for one point.
- The catalog is read from workflow blobs only when the tree OID changes, and
  a failed catalog fetch keeps the previous catalog and clears the OID so the
  next refresh retries.
- `--activity` is a refresh mode of the existing command rather than a new
  command so the native app keeps one decode path and one scan state.
- The cache stays at version 1 with additive optional fields. An older binary
  that reads a cache holding `workflows` quarantines it once and rebuilds on
  its next refresh; a version bump would quarantine unconditionally.
- Governor reasons are stable strings mirrored natively; only `interval`
  denials are retried by the app, every other denial stops the loop.
- Freshness for animation is two minutes; polling eligibility uses the
  governor's active-run count so an old cached active run triggers exactly
  one corrective poll rather than animating.
- The Constitution's "never by a continuous timer" invariant is amended to
  permit exactly this bounded, self-terminating, quota-gated follow-up.
- Polls never refresh pull-request rows. When a poll result shows rows past
  the five-minute floor, the app runs the ordinary stale refresh instead of
  letting a watched deploy demote every row to cached; that costs the same
  bounded refresh a foreground activation would.
- The burst clock lives in the cache so every helper process shares it. A
  poll that observes completion closes it, active work created after the
  burst started restarts it, and unconfigured cache entries never count.

## DISCOVERIES

- The unmodified batch already cost 115 points for the twenty-three watched
  repositories (five per repository: the pull-request connection plus the
  four per-pull-request glance connections). Spec 0004's "cost 16 for 16
  repositories" predates the glance fields. The repository-level additions
  here cost about one more point; catalog reads and activity polls cost one.
- The REST `rate_limit` endpoint reports a different GraphQL usage figure than
  the GraphQL `rateLimit` object; only the latter is trustworthy for cost.
- `object(expression: "HEAD:.github/workflows")` returns `null` for
  repositories without workflows; that is an empty catalog, not an error.
- Window occlusion is the right native "someone is looking" signal. The first
  packaged-app run also gated on app activation and stopped after one poll as
  soon as the terminal took focus, although the window stayed visible beside
  it; activation was dropped so a visible Hyperlite next to an editor keeps
  polling. The hotkey path shows the window, so it needs no separate hook.

## VALIDATION

- `make fmt-check vet test test-race build` PASS. Go coverage includes query
  shape (no blobs and no head suites in the batch), catalog parsing and
  fallback, run mapping and merge, pending-head follow-up, poll decoding with
  dropped and merged pull requests, catalog reuse on unchanged tree OID,
  catalog failure retention, denied poll touching nothing, poll failure
  keeping `observed_at`, legacy hydration, cache round trip and legacy load,
  window counting, every governor reason with boundaries, and CLI mode and
  exclusivity.
- `make macos-test macos-build` PASS with `codesign --verify --deep --strict`.
  Swift coverage includes decoding with and without the new fields, chip
  derivation and ordering, the 119/121-second freshness boundary, synthetic
  deployment chips, labels and header summary, compact collapse, hover
  snapshot, glide math and tick rate, section plan ordering and URLs, every
  schedule stop reason and interval retry, and the stacked height estimate.
- Isolated-cache live scans (`HYPERLITE_PULL_REQUEST_CACHE_PATH`): a forced
  refresh populated catalogs for all twenty-three projects with zero errors;
  a second forced refresh issued no catalog query; the batch cost 116 points
  against the 115-point baseline measured with the unmodified `main` binary;
  `--activity` cost one point and reported `ok` with `polls_this_window` 1.
- Source-file-size audit: every touched Go and Swift source or test file is at
  or under 300 lines (largest `cache.go` 286, `HyperlitePullRequestTests.swift`
  284).
- Packaged-app observation (signed `build/Hyperlite.app` launched against an
  isolated cache): the launch refresh recorded four active runs and started
  the burst; the first `--activity` poll ran 69 seconds later at one point.
  Under the original app-activation gate the loop then stopped as soon as the
  terminal took focus, which led to dropping that gate. On the rebuilt app the
  poll ran 73 seconds after the burst started, observed that every watched
  run had completed, and correctly stopped with no further helper
  invocations. A multi-poll cadence was not observed live because no watched
  run outlasted the first poll; the schedule and service tests cover it.
- Independent read-only verification ran after implementation and found a
  burst clock that could pin polling off (fixed: polls now close the burst,
  newer work restarts it, and only configured repositories count), a changed
  tree without a catalog result recorded as current (fixed: tree OID cleared
  so the next refresh fetches), and row demotion to cached after five
  minutes during a watched deploy (fixed: a stale poll result triggers the
  ordinary stale refresh). Lower-severity items were also taken: transport
  failures retry on the schedule, window visibility is seeded at launch, a
  null default branch drops stale tip runs, and dead availability code was
  removed.

## OUTCOME

Every configured project now owns an Open PRs section with Pulls and Actions
buttons and a strip of its workflows. A workflow observed running within the
last two minutes glides a small ghost along a track with its elapsed time;
older active data says when it was last seen. The batch adds one point, the
catalog is read only when workflow files change, and a quota-governed poll
keeps running work current for at most thirty minutes at one point per
minute, only while the window is visible.

## REPOSITORY MEMORY

- Decision: created
- Rationale: the quota governor thresholds, the batch cost discovery, the
  join-key and freshness rules, and the Constitution amendment are product
  decisions that code and tests cannot preserve alone.
- Artifacts: `docs/specs/0031-open-pr-workflow-activity/SPEC.md`,
  `docs/CONSTITUTION.md`, `docs/USER_GUIDE.md`, `README.md`,
  `docs/references/testing.md`, `docs/PROJECT_PROGRESS_SUMMARY.md`,
  `docs/specs/0027-open-pr-project-sections/SPEC.md`,
  `docs/specs/0004-open-pull-requests/SPEC.md`
