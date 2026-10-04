---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0038"
  slug: open-pr-api-budget
  dir: 0038-open-pr-api-budget
references:
  - id: issue-113
    name: "Minimize GitHub API usage from Open PR refreshes"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/113
    relation: implements
    read_policy: must
    used_for: accepted scope and acceptance
    status: active
  - id: open-pr-fetch-reliability
    name: Open PR Fetch Reliability
    type: specification
    target: docs/specs/0037-open-pr-fetch-reliability/SPEC.md
    relation: amends
    read_policy: must
    used_for: probe-then-detail fetch this builds on
    status: active
skills: []
---

# Open PR API Budget

## PURPOSE

Keep Hyperlite's ambient Open PR refresh from consuming the GitHub GraphQL
quota that every `gh` caller on the machine shares.

## CONTEXT

After 0037, an automatic refresh of 102 repositories cost ~45 points (11 probe
points plus ~30 detail points and occasional workflow catalogs). With the
one-minute ambient check and five-minute floor, a visible window could spend
~500 points an hour, mostly re-reading pull requests that had not changed.

Orchestration: single-lane, because reuse and the quota pause share one cache
and refresh contract.

## REQUIREMENTS

- R1: An automatic refresh of an unchanged watch list costs only the probe.
- R2: Automatic refreshes stop spending quota when it is low; explicit Refresh
  is never blocked.
- R3: Row data that can change without bumping a pull request's `updatedAt`
  (CI rollup, mergeability) is never older than fifteen minutes.

## ACCEPTED PLAN

1. The probe also reads the newest open pull request's `updatedAt`.
2. Automatic refreshes pass a cached listing hint (open count, newest
   `updatedAt`, rows, pull-request workflow runs) per repository; a matching
   probe reuses the cached rows and skips the detail query.
3. Track `detail_checked_at` per repository; reuse never renews it.
4. Pause stale-mode network work below max(1,000, 20% of limit) remaining in
   the current window and report a `pull-request-quota` warning.

## DECISIONS

- Fingerprint by open count plus newest `updatedAt`. A new push, review,
  comment, label, or title edit bumps `updatedAt`; an added or closed pull
  request changes the count or the newest timestamp.
- Never reuse while any cached rollup is pending, and re-read details at least
  every fifteen minutes, because CI and mergeability change silently.
- A forced Refresh passes no hints and ignores the pause: the operator asked.
- The automatic floor (20%) sits below the activity poll floor (30%), so the
  poll stops first and pull-request rows keep refreshing longest.

## VALIDATION

- Go tests cover hint eligibility (pending CI, stale details, errors, never
  read), probe reuse with carried pull-request runs, re-reading on a changed
  fingerprint, the quota pause boundaries, and that a paused stale scan makes
  no client call while a forced scan passes no hints.
- Live, 102 repositories with an isolated cache: forced refresh 45 points;
  automatic refresh after the floor 11 points (probes only), 100 current with
  151 open pull requests.

## OUTCOME

- An idle visible window now spends ~130 points an hour instead of ~500, and
  automatic refresh stops entirely when the shared quota runs low.

## REPOSITORY MEMORY

- Rationale here; CONSTITUTION records that quota may only deny automatic work;
  USER_GUIDE records reuse and the pause.
