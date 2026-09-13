---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0034"
  slug: open-pr-collapsible-sections
  dir: 0034-open-pr-collapsible-sections
references:
  - id: issue-104
    name: "Open PRs: collapsible project sections + clear stale error banner"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/104
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-watch-stage
    name: Open PR Watch Stage
    type: specification
    target: docs/specs/0033-open-pr-watch-stage/SPEC.md
    relation: constrains
    read_policy: must
    used_for: lantern stages, hide-idle collapsible list, section header chrome
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Open PR panel presentation
    status: active
skills: []
---

# Open PR Collapsible Sections

## PURPOSE

Make the Open PRs pane scannable by project: give each project heading a
larger type than its pull-request rows, let a project collapse its rows
behind a chevron while keeping the name and open-PR count, and stop a stale
error banner from lingering after a successful refresh.

## CONTEXT

After 0033 the pane reads as project clusters marked by a thin lantern, but a
project heading is only bolder than its rows, not larger, and a busy project's
rows cannot be folded away. Separately, a transient scan failure could leave a
`The data couldn't be read because it is missing.` banner stuck: a successful
pull-request refresh set the scan but never cleared `errorMessage`. The
0033 watch-stage removal made this visible because dropping the `commit_count`
cache fields caused the pull-request cache to be rebuilt once on first launch.

Orchestration: single-lane, because the heading size, per-project collapse,
and error-clear all live in the same Open PRs presentation path.

## REQUIREMENTS

- R1: An active project heading (a project with open pull requests) uses a
  font larger than its pull-request rows, sitting between the row type and the
  `Open PRs` pane title.
- R2: A project with open pull requests can collapse its rows with a chevron
  at the left of its heading. Collapsed keeps the project name, open-PR count,
  workflow chips, and GitHub buttons visible and hides only the rows. An idle
  project (no rows) shows no chevron.
- R3: Collapse state persists per project across refreshes and launches, keyed
  by project id.
- R4: A successful pull-request refresh clears a previously shown error banner,
  so a transient failure does not persist once valid data loads. A refresh that
  fails still shows its error.
- R5: Keep the project name button opening the repository, drag-and-drop pin
  reordering, hover behavior, and the hide-idle collapsible list unchanged.
- R6: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Changing hide-idle membership or the `watching the quiet ones` list.
- Collapsing the Pinned section or idle projects.
- Reworking the shared error/status channel beyond clearing it on success.

Observable acceptance:

- Project names are visibly larger than their pull-request rows.
- Clicking a project's chevron hides its rows and leaves the name plus count;
  clicking again restores them, and the choice survives a refresh.
- The `The data couldn't be read because it is missing.` banner disappears on
  the next successful refresh instead of sticking.

## ACCEPTED PLAN

1. Add a `HyperliteTypography.sectionHeading` (semibold, body size + 2) and use
   it for the active heading weight so names outsize rows.
2. Give `HyperliteProjectSectionHeader` an optional `collapsed` binding that
   renders a leading chevron toggle; wrap each project cluster in a new
   `HyperliteOpenPRProjectSection` that owns per-project `@AppStorage` collapse
   state and hides the rows when collapsed. Only sections with rows collapse.
3. Clear `errorMessage` in `HyperliteState.refreshPullRequests` when a scan is
   applied successfully.
4. Cover collapse gating and the storage-key format with a presentation test.

## DECISIONS

- Collapse state is per-project `@AppStorage`, keyed by project id, so a
  folded project stays folded across refreshes and relaunches without a new
  store.
- The collapse toggle is an explicit chevron rather than a whole-heading tap,
  so the project name keeps opening the repository and the GitHub buttons keep
  their own hit targets.
- Only projects with rows collapse; an idle heading has nothing to hide, which
  also keeps the hide-idle `watching the quiet ones` list (idle sections)
  chevron-free.
- The error banner clears on a successful scan rather than by re-architecting
  the shared error/status channel; a successful data load is the right moment
  to drop a stale transient error for this pane.

## VALIDATION

- `make macos-test` passed: full app typecheck plus Swift model tests,
  including the new collapse-gating and storage-key test.
- `make macos-build` produced `build/Hyperlite.app`. Native screenshot
  evidence is SKIPPED (ScreenCaptureKit).

## OUTCOME

- Open PRs headings are larger than their rows and each busy project folds
  behind a persisted chevron; a stale error banner no longer lingers after a
  successful refresh. Ready pull-request delivery through issue #104.

## REPOSITORY MEMORY

- Feature rationale lives in this spec. USER_GUIDE records the larger,
  collapsible project headings. The error-clear rationale is captured here as
  the fix for a stale banner after the 0033 cache-field removal.
