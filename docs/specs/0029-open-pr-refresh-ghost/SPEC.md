---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0029"
  slug: open-pr-refresh-ghost
  dir: 0029-open-pr-refresh-ghost
references:
  - id: issue-92
    name: Show a ghost pulse while Open PRs refresh
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/92
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
    used_for: cached rows stay available during refresh
    status: active
  - id: runtime-resource-cut
    name: Runtime Resource Cut
    type: specification
    target: docs/specs/0018-runtime-resource-cut/SPEC.md
    relation: constrains
    read_policy: must
    used_for: idle CPU stays near zero; no extra helpers or polling
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Open PR header presentation
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Swift presentation tests and macos-test
    status: active
skills: []
---

# Open PR Refresh Ghost

## PURPOSE

Let the operator see that Open PRs are still fetching GitHub data, using a
tiny ghost pulse that costs almost no idle CPU.

## CONTEXT

Open PRs keep cached rows on screen while a refresh runs. The header currently
looks idle, so a long GraphQL update reads as a frozen list. The first load
uses a spinning `ProgressView`.

The operator chose a ghost pulse: the Open PRs title quietly brightens and a
tiny 👻 fades about every 1.2s. Rejected alternatives were orbiting dots, a
sparkle cycle, a cyan scanline, and typed `gh is looking…` copy.

Orchestration: single-lane, because pulse math, header chrome, first-load,
Notes Only, and tests share one presentation contract.

## REQUIREMENTS

- R1: While `isRefreshingPullRequests` is true, the Open PRs title and a 👻
  glyph pulse on a ~1.2s `TimelineView` tick. The pulse is gone when refresh
  ends.
- R2: Cached rows stay visible and interactive. No dimming veil over the
  list.
- R3: First load (no scan yet) uses the same header pulse, not a spinner.
- R4: Notes Only summary pulses during refresh.
- R5: No extra GitHub calls, no 60fps repeating animation, no blur, no
  particles. Discrete opacity ticks only.
- R6: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Changing refresh cadence, cache, or pin/section behavior.
- Overlaying or disabling Open PR rows during refresh.

Observable acceptance:

- Refresh shows a 👻 pulse on the Open PRs header; it stops when the fetch
  completes.
- Cached PRs remain readable during refresh.
- After refresh, no TimelineView remains in the tree.

## ACCEPTED PLAN

1. Extract pulse interval, brightness phase, opacity, and accessibility into
   a testable presentation helper.
2. Drive the header with `TimelineView(.periodic)` only while refreshing.
3. Replace the first-load `ProgressView` with the same header pulse.
4. Pulse the Notes Only summary with the same helper.
5. Cover phase, opacity, glyph visibility, and accessibility with Swift tests.

## DECISIONS

- Discrete 1.2s ticks instead of `repeatForever` interpolation. A 60fps
  opacity animation would keep the display busy for the whole fetch.
- Keep the 👻 in layout while refreshing and fade opacity, so the header does
  not jump.
- Header-only, not a list overlay. Constitution requires cached rows to stay
  available during refresh.
- User-facing copy stays “Refreshing open pull requests from GitHub”. The
  helper still uses GraphQL via `gh`; the pulse does not mention `gh`.

## DISCOVERIES

- `kit spec open-pr-refresh-ghost` rewrote `docs/PROJECT_PROGRESS_SUMMARY.md`
  wholesale. Restored the curated index and added only the 0029 row and
  summary.

## VALIDATION

- `make macos-test` PASS: native type-check plus executable tests, including
  idle opacity, 1.2s bright/dim phases, glyph visibility while refreshing, and
  VoiceOver copy.
- Source-file-size audit of the affected handwritten scope:
  `HyperliteOpenPRRefreshPulse.swift` 86, `HyperliteViews.swift` 264,
  `HyperlitePullRequestPanel.swift` 123,
  `HyperliteOpenPRRefreshPulseTests.swift` 68,
  `HyperliteInteractionModelTests.swift` 277.
- Interactive packaged-app walkthrough SKIPPED.

## OUTCOME

While Open PRs refresh, the heading and a tiny 👻 pulse on discrete 1.2s
ticks. Cached rows stay readable. First load uses that same heading pulse
instead of a spinner. Notes Only pulses the same way. The timeline is not in
the view tree after refresh ends.

## REPOSITORY MEMORY

Created `docs/specs/0029-open-pr-refresh-ghost/SPEC.md` for the chosen ghost
pulse, rejected alternatives, and the discrete-tick CPU contract. Constitution
unchanged: cached rows during refresh is already a project-wide invariant, and
the pulse is feature-local presentation. User guide and testing reference
updated.

Feature 0030 supersedes the heading-only pulse with a pane-filling spinning
overlay.

