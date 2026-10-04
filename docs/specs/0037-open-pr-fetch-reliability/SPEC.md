---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0037"
  slug: open-pr-fetch-reliability
  dir: 0037-open-pr-fetch-reliability
references:
  - id: issue-110
    name: "Open PRs missing for configured projects; expand watch list, prune dead code, ambient refresh"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/110
    relation: implements
    read_policy: must
    used_for: accepted scope, RCA, and observable acceptance
    status: active
  - id: open-pull-requests
    name: Open Pull Requests
    type: specification
    target: docs/specs/0004-open-pull-requests/SPEC.md
    relation: amends
    read_policy: must
    used_for: GraphQL batching and cache refresh contract
    status: active
  - id: open-pr-refresh-ghost-overlay
    name: Open PR Refresh Ghost Overlay
    type: specification
    target: docs/specs/0030-open-pr-refresh-ghost-overlay/SPEC.md
    relation: supersedes
    read_policy: optional
    used_for: the removed full-pane refresh ghost
    status: active
  - id: open-pr-workflow-activity
    name: Open PR Workflow Activity
    type: specification
    target: docs/specs/0031-open-pr-workflow-activity/SPEC.md
    relation: amends
    read_policy: optional
    used_for: the removed gliding ghost under running chips
    status: active
  - id: dashboard-list-organization
    name: Dashboard List Organization
    type: specification
    target: docs/specs/0008-dashboard-list-organization/SPEC.md
    relation: supersedes
    read_policy: optional
    used_for: the removed sort, filter, and reorder model
    status: active
  - id: source-file-size
    name: Source File Size
    type: ruleset
    target: docs/references/rules/source-file-size.md
    relation: constrains
    read_policy: must
    used_for: keep handwritten source and test files at or under 300 lines
    status: active
skills: []
---

# Open PR Fetch Reliability

## PURPOSE

Make Open PRs show every open pull request for every configured project, keep
the list current without operator action, and remove dead code and retired
decoration so the app loads and refreshes faster.

## CONTEXT

Observed on 2026-10-03: every configured project reported `gh: HTTP 502`.
`checked_at` advanced each refresh while `observed_at` stayed at 2026-09-30, so
the window kept showing a days-old cache (4 pull requests instead of 91).

Root cause: `queryBatchSize = 25` put all 23 configured repositories into one
GraphQL query. Each repository costs roughly 0.4-1.4s of GitHub server time
(100 pull requests with review threads, commits, status rollups, plus
default-branch check suites and deployments). The 23-repository query took
~10.9s, crossed GitHub's ~10s gateway timeout, and a batch-level failure marked
every repository in the batch as failed. A second contributor: `gh api graphql`
exits non-zero whenever the response carries any GraphQL error, even a
repository-scoped one such as a deleted repository, so one missing repository
also failed its whole batch.

Orchestration: multi-lane for discovery and cleanup only. A read-only mapper
inventoried dead code and retired features; a Go specialist removed dead Go
code while the Swift removals proceeded in parallel on disjoint files. The
fetch redesign and ambient refresh stayed single-lane because they share one
cache and refresh contract.

## REQUIREMENTS

- R1: A slow, missing, or failing repository never fails another repository's
  Open PR rows.
- R2: A forced refresh of the full watch list completes well inside GitHub's
  gateway timeout per request and within a bounded GraphQL cost.
- R3: While the window is visible, Open PRs refresh without operator action;
  revealing the window or waking the Mac catches up immediately. The existing
  five-minute per-repository floor still bounds GitHub cost.
- R4: Remove retired decoration (the full-pane refresh ghost, the gliding ghost
  under running chips) and code no production path reaches.
- R5: Keep handwritten source and test files at or under 300 lines.

Non-goals: removing the agent-session, thread-scan, or pinboard CLI commands.
They are unused by the window, but installed Claude Code and Codex hooks still
invoke `hyperlite-cli agent hook`, so removing them needs an operator decision.

## ACCEPTED PLAN

1. Probe repositories in batches of ten for `pullRequests(states: OPEN) {
   totalCount }` plus repository activity. A zero count is final: empty rows,
   activity kept. A repository-scoped GraphQL error is final. A failed probe
   batch falls back to detail queries.
2. Query pull-request details one repository per request, concurrently
   (bounded at ten in-flight `gh` processes), starting as soon as each probe
   batch returns. Size the first page from the probe count.
3. Treat a non-zero `gh` exit whose stdout still holds GraphQL `data` as a
   response and attribute errors per alias.
4. Inspect repositories concurrently during discovery.
5. Add an ambient refresh loop in the native app and wake/reveal triggers.
6. Remove retired animations and dead Swift and Go code.

## DECISIONS

- One repository per detail query instead of smaller batches with
  split-and-retry. Per-repository latency is the whole cost, so batching saves
  nothing but process spawns, while one-per-request makes isolation structural
  and needs no retry logic.
- Probe before detail. GraphQL cost scales with requested page sizes, not
  returned rows, so most repositories (no open pull requests) were paying for
  100-row pages. Sizing pages from the probe count cut a full refresh of 102
  repositories from ~700 points to ~41.
- The ambient loop asks for a stale refresh every minute rather than forcing a
  refresh every five. The Go helper already skips repositories inside the
  five-minute floor, so the loop stays cheap and the list never ages much past
  that floor.
- Replace the full-pane refresh ghost with a small title spinner. With ambient
  refresh, a pane-sized animation every few minutes would be a distraction.
- Remove the dashboard sort/filter/reorder model (0008) and the hide-drafts
  filter (0014). Their only UI was a filter popover no view presented; pin
  membership and order live in the pin store and are unchanged.

## DISCOVERIES

- `gh api graphql` returns exit status 1 with a complete JSON body whenever the
  response has `errors`; callers must inspect stdout before treating the exit
  as a transport failure.
- Discovery ran ~4 sequential `git` processes per repository, ~4s for 102
  repositories, on every refresh including the cache-only startup load.
- The planet/orbit animation had already been removed in #103; it survives only
  as superseded history in 0033.

## VALIDATION

- `make fmt-check vet test-race build macos-test macos-build` passed.
- New Go tests cover one-repository detail queries with probe-sized pages,
  failing-repository isolation, data-bearing non-zero `gh` exits, probe
  zero-count skips, probe fallback, final probe errors, and rate-limit merging.
- Swift tests cover the ambient refresh schedule.
- Live, against the operator's watch list: 23 repositories went from 23 x HTTP
  502 to 23 current with 91 open pull requests. After expanding to 102
  repositories, a forced refresh returned 100 current with 150 open pull
  requests in ~7s (was ~17.5s) using ~41 GraphQL points (was ~700), and the
  cache-only load took ~1.0s (was ~4.2s). Two repositories are reported
  unavailable because their remotes no longer exist on GitHub.

## OUTCOME

- Open PRs shows every resolvable configured repository's pull requests, keeps
  itself current while visible, and no single repository can blank the list.
  Roughly 3,000 lines of dead code and decoration were removed. Ready
  pull-request delivery through issue #110.

## REPOSITORY MEMORY

- This spec holds the RCA and fetch design rationale. CONSTITUTION records the
  per-repository failure-isolation invariant. USER_GUIDE records ambient
  refresh, the probe-then-detail fetch, the title spinner, and the still
  running-chip dot. testing.md records the new coverage.
