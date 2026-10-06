---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0045"
  slug: undeployed-merges
  dir: 0045-undeployed-merges
references:
  - id: issue-159
    name: "Show merged PRs whose deploy pipeline failed (NOT DEPLOYED triage band)"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/159
    relation: implements
    read_policy: must
    used_for: accepted scope and the chosen triage-band design
    status: active
  - id: open-pr-layout-and-scroll
    name: Open PR Layout And Scroll
    type: specification
    target: docs/specs/0044-open-pr-layout-and-scroll/SPEC.md
    relation: amends
    read_policy: optional
    used_for: the flat list item model the band extends
    status: active
skills: []
---

# Undeployed Merges

## PURPOSE

Make it obvious which merged pull requests never reached a deployment, so an
Actions outage that left deploy pipelines failed or skipped can be triaged and
re-run project by project.

## CONTEXT

On 2026-10-05 a GitHub Actions outage failed CI on many default branches.
Deploy workflows in these repositories trigger on `workflow_run` after CI, so
most deploys were **skipped**, not failed. The existing persistent deploy
alert only sees check suites on the current tip commit and only recognized
workflows whose name starts with `deploy`. It flagged one repository while
four had merged, undeployed work.

The operator chose the "triage band" option out of three: a NOT DEPLOYED band
above all organizations that lists each behind project, its failed or skipped
pipeline with a re-run link, and the merged pull requests waiting. Each behind
project heading gets an amber `🚀✕N` badge, and a quick fact counts the
undeployed pull requests.

Orchestration: single-lane, because the Go detection, the cache field, and the
Swift band share one data contract and each step depends on the previous one.

## DECISIONS

- **Behind means an attempt after the last success did not deploy.** For each
  deploy workflow, sort the default-branch runs newest first (the REST listing
  is not reliably ordered). A pipeline is behind when, since its last success,
  a run failed, was cancelled, or was skipped on an automatic trigger (`push`,
  `workflow_run`, or `dynamic`). A newest run that is still in progress is not
  behind. Without a success in the window, only a real failure counts, so a
  conditional workflow that always skips (labcore's Mint Production) is never
  flagged.
- **Undeployed pull requests are the merges after the oldest last success.**
  The cutoff is the successful run's head commit timestamp plus 10s of slack,
  because GitHub's `merged_at` trails the merge commit by about a second. A
  skip-only gap with no undeployed merges is dropped, for example a manual
  redeploy of the same commit. A failed gap stays even with no merges, since
  direct pushes are also undeployed.
- **REST, not GraphQL, and only when something changed.** One `actions/runs`
  listing per repository, plus one `pulls` listing only when behind. Neither
  spends GraphQL points. A repository is rechecked only when its fingerprint
  changes (tip OID plus deploy tip-run states), every 20 minutes while behind,
  or every 6 hours otherwise. A failed check keeps the cached gap and retries
  after 15 minutes. A repeat forced refresh made zero deploy requests.
- **Broader deploy classification.** A workflow counts as a deploy when its
  file stem or name contains `deploy`, or has a `pages`, `production`, `prod`,
  `prd`, or `promote` word. Release and publish workflows build artifacts and
  are not deploys. Dynamic GitHub-managed runs are classified by path only,
  because Dependabot run names such as `pip in /deploy` would otherwise count.
- **Amber, not red.** CI failures stay red beside each row. The band uses the
  theme orange with a faint tint, and the badge is a tinted capsule. It is a
  call to re-run a deploy, not a broken build. When a project is behind, the
  badge replaces that heading's deploy alert so it is not shown twice.
- **Hidden projects still appear in the band.** Undeployed merges matter most
  exactly when nothing is open, so the band ignores hide-idle. Ignored
  projects are never fetched and never appear.

## VALIDATION

- `make fmt-check vet test-race build macos-test macos-build` passed.
- Live run against the operator's watch list on 2026-10-06 found 13 pull
  requests across lsmc-bio/labcore, flowcore, event-sink, and status, matching
  their Actions history. labcore PR #1130, deployed by the last successful
  run, is correctly excluded.

## OUTCOME

- Open PRs leads with a collapsible NOT DEPLOYED band when any deploy is
  behind. Its project and pull-request lines are keyboard-navigable and open
  the run or pull request. Behind headings carry `🚀✕N`, and the top bar shows
  `N not deployed`.
