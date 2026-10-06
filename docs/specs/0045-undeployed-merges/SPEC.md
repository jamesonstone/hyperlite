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
  deploy workflow, read its runs on the default branch's recent commits,
  newest first. A pipeline is behind when, since its last success,
  a run failed, was cancelled, or was skipped on an automatic trigger (`push`,
  `workflow_run`, or `dynamic`). A newest run that is still in progress is not
  behind. Without a success in the window, only a real failure counts, so a
  conditional workflow that always skips (labcore's Mint Production) is never
  flagged.
- **Undeployed pull requests are the merges after the oldest last success.**
  The cutoff is the successful run's commit time plus 10s of slack, because
  GitHub's `merged_at` trails the merge commit by about a second. The pull
  requests come from each newer commit's associated pull request. A
  skip-only gap with no undeployed merges is dropped, for example a manual
  redeploy of the same commit. A failed gap stays even with no merges, since
  direct pushes are also undeployed.
- **Commit history, not run listings, and only when something changed.**
  GraphQL reads default-branch commits 50 per page, about 1 point a page. It
  stops once the commits reach past the 30-day retirement window and every
  behind pipeline has found its last success, with at most 4 pages. A commit
  whose Actions suites overflow a page is completed with follow-up pages, so
  no deploy attempt is silently missing. One aquarium commit has 75 suites.
  GraphQL resource paths such as `/o/r/actions/workflows/deploy.yml` map to
  `.github/workflows/...`, and GitHub-managed subfolders map to `dynamic/...`,
  so classification still ignores per-run names on those. Each commit comes with its GitHub Actions check
  suites (workflow run, event, conclusion) and the pull request that produced
  it. A repository is rechecked only when its fingerprint changes (tip OID
  plus deploy tip-run states), every 20 minutes while behind, or every 6
  hours otherwise. A failed check keeps the cached gap and retries after 15
  minutes. The fingerprint carries a version, so a fix to the detection
  rechecks every repository once.
- **Superseded: REST run listings (#160 to #162).** The first design read
  `actions/runs?branch=` and closed `pulls` pages to avoid GraphQL points. On
  2026-10-06, after the Actions outage, those listings served lagging,
  inconsistent pages:
  - `total_count` changed from page to page (258, then 184, then 698).
  - The "newest" runs were weeks old.
  - The per-workflow listing randomly ended days early.

  Guards on page shape (#162) and on tip-run presence could not catch a page
  that was complete but outdated. The cached "no gap" results then hid every
  real gap and emptied the band. Commit check suites stayed current
  throughout, so detection moved to them (#165).
- **Retired pipelines are not behind.** A deploy whose newest attempt is
  older than 30 days is dropped before the cutoff is chosen, so it cannot
  widen the undeployed list of an active pipeline. lsmc-vivarium's `deploy-dev` last failed in
  August and would otherwise list every merge since June.
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
