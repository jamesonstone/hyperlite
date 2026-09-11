---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0030"
  slug: open-pr-refresh-ghost-overlay
  dir: 0030-open-pr-refresh-ghost-overlay
references:
  - id: issue-94
    name: Overlay a spinning ghost across Open PRs while GitHub refreshes
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/94
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-refresh-ghost
    name: Open PR Refresh Ghost
    type: specification
    target: docs/specs/0029-open-pr-refresh-ghost/SPEC.md
    relation: supersedes
    read_policy: must
    used_for: header-only pulse is too small; overlay replaces it
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
    used_for: idle CPU stays near zero; overlay ticks only while refreshing
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Open PR pane presentation
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

# Open PR Refresh Ghost Overlay

## PURPOSE

Make the in-flight Open PR refresh obvious: a large ghost overlays the whole
Open PR pane and spins a full turn, pauses at rest, then spins again.

## CONTEXT

Feature 0029 put a tiny heading pulse next to Open PRs. Operators could miss
it. The accepted change is a pane-filling overlay with a 360° spin and a
brief pause at 0°.

Orchestration: single-lane, because overlay math, pane coverage, Notes Only,
header cleanup, and tests share one presentation contract.

## REQUIREMENTS

- R1: While `isRefreshingPullRequests` is true, a large 👻 overlays the entire
  Open PR side view and rotates 360°, pauses at 0°, then repeats.
- R2: Cached rows stay visible and interactive. The overlay does not capture
  clicks and does not dim the list into unreadability.
- R3: First load (no scan yet) uses the same overlay, not a spinner.
- R4: Notes Only still shows the spinning overlay over its Open PR chrome.
- R5: No extra GitHub calls, no blur, no particles. Rotation updates only
  while refreshing, at a low tick rate well below display refresh. Idle has
  no TimelineView.
- R6: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Changing refresh cadence, cache, or pin/section behavior.
- Blocking or hiding Open PR rows during refresh.

Observable acceptance:

- Refresh shows a large spinning 👻 over the Open PR pane; it stops when the
  fetch completes.
- Cached PRs remain readable and clickable during refresh.
- After refresh, no TimelineView remains in the tree.

## ACCEPTED PLAN

1. Replace heading opacity ticks with rotation and overlay fill math in the
   existing pulse helper.
2. Overlay the Open PR column (and Notes Only chrome) only while refreshing.
3. Restore a static Open PRs heading so the tiny header ghost is gone.
4. Cover rotation phases, pause-at-zero, idle rest, and accessibility with
   Swift tests.

## DECISIONS

- 12 Hz `TimelineView` ticks derive rotation from wall-clock time. That is a
  visible spin without a 60fps `repeatForever` animation. Feature 0029's
  1.2s opacity blink is superseded because it was too small to notice.
- Overlay fill uses the shorter pane axis so stacked and Vertical Mode both
  get a large ghost. Opacity stays translucent so rows remain readable.
- `allowsHitTesting(false)` keeps cached rows interactive. Constitution still
  requires rows to stay available during refresh.
- Pause at 0° is a hold after a completed turn, not a reverse spin.

## DISCOVERIES

- `kit spec` rewrites `docs/PROJECT_PROGRESS_SUMMARY.md` wholesale. Keep the
  curated index and add only the 0030 row and summary.
- First load has no pull-request panel, so VoiceOver must ride the title
  cluster. The overlay stays accessibility-hidden so cached rows remain
  the primary accessible content after a scan exists.

## VALIDATION

- `make macos-test` PASS: native type-check plus executable tests, including idle
  rest at 0°, mid-spin 180°, pause-at-zero, overlay visibility, 12 Hz ticks, and
  VoiceOver copy.
- Source-file-size audit of the affected handwritten scope:
  `HyperliteOpenPRRefreshPulse.swift` 80, `HyperliteViews.swift` 261,
  `HyperlitePullRequestPanel.swift` 122,
  `HyperliteOpenPRRefreshPulseTests.swift` 81,
  `HyperliteInteractionModelTests.swift` 277.
- Interactive packaged-app walkthrough SKIPPED.

## OUTCOME

While Open PRs refresh, a large translucent 👻 overlays the pane, spins
360° on 12 Hz ticks, pauses at rest, then spins again. Cached rows stay
readable and clickable. First load and Notes Only use the same overlay. The
timeline is not in the view tree after refresh ends.

## REPOSITORY MEMORY

Created `docs/specs/0030-open-pr-refresh-ghost-overlay/SPEC.md` for the
pane-filling spin, pause-at-zero, and low-tick overlay contract. Feature 0029
records that 0030 supersedes the heading-only pulse. Constitution unchanged:
cached rows during refresh remains the project-wide invariant. User guide
and testing reference updated.
