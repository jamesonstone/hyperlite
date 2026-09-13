---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0033"
  slug: open-pr-watch-stage
  dir: 0033-open-pr-watch-stage
references:
  - id: issue-102
    name: "Open PRs watch stage: readable clusters, leftover ghost sky, keep every hover"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/102
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-design-pass
    name: Open PR Design Pass
    type: specification
    target: docs/specs/0032-open-pr-design-pass/SPEC.md
    relation: constrains
    read_policy: must
    used_for: title hierarchy, hide-idle membership, heading weight, chrome indent
    status: active
  - id: open-pr-ready-inline
    name: Open PR Ready Inline
    type: specification
    target: docs/specs/0028-open-pr-ready-inline/SPEC.md
    relation: supersedes
    read_policy: must
    used_for: "Vertical Mode compact rows: ready stays a whole word; unpinned rows become two-line stacks"
    status: active
  - id: readable-workspace-layout
    name: Readable Workspace Layout
    type: specification
    target: docs/specs/0025-readable-workspace-layout/SPEC.md
    relation: constrains
    read_policy: must
    used_for: two-pane Vertical Mode and stacked leftover-height-for-notes
    status: active
  - id: runtime-resource-cut
    name: Runtime Resource Cut
    type: specification
    target: docs/specs/0018-runtime-resource-cut/SPEC.md
    relation: constrains
    read_policy: must
    used_for: hidden-idle list has no idle TimelineView or size poll
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Open PR panel presentation
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

# Open PR Watch Stage

## PURPOSE

Make Vertical Mode's Open PRs pane readable: lantern-marked project
clusters, two-line titles, quieter drag chrome, and hidden idle projects
kept in a standard collapsible list.

## CONTEXT

The two-pane split and notes pane are the right shape. After 0032 the Open
PRs column still reads as a sparse utility list: unpinned titles share one
line with `ready`/`draft` and truncate, drag chrome competes at rest, and
hide-idle simply drops idle projects with no way to glance at them. Feature
0028 kept unpinned compact rows on one line so `ready` would not wrap; this
pass keeps `ready` a whole word by moving it onto the identity line and
giving the title its own line.

Orchestration: single-lane, because stages, compact-row stacking, and the
hidden-idle collapsible list share one presentation contract and need
continuous design judgment.

## REQUIREMENTS

- R1: Vertical Mode compact rows are two lines for pinned and unpinned
  rows. Identity (`#number`, `ready`/`draft`, conflict, review) stays on
  line one as whole words. Title plus age sit on line two. Stacked
  (non-compact) rows stay one line.
- R2: Each visible project cluster, and Pinned when it has rows, is marked
  by a thin left lantern. Running or failing work lights that lantern cyan.
  No filled cards.
- R3: When hide-idle is on in Vertical Mode, hidden idle projects appear
  below the open work in a standard collapsible list captioned `watching
  the quiet ones` with the hidden count. It is collapsed by default;
  expanding it shows each hidden project's heading with the same idle
  availability text, workflow chips, and Pulls/Actions links as an inline
  idle section. Hide-idle membership does not change. Showing idle projects
  (eye off) lists them inline instead. Stacked (non-compact) layout shows no
  collapsible list, so its leftover height still goes to notes.
- R4: Drag handles, unpinned pins, and empty review boxes are quieter at rest
  and full on row hover. Number→issue, title→PR, Pulls/Actions, running
  chips, hover cards, and the refresh overlay stay. Compact Pulls/Actions
  wait on heading hover. Compact headings use the short repository name;
  hover names the full GitHub path. Running GitHub Actions chips keep their
  12 Hz gliding 👻.
- R5: The hidden-idle list uses a native `DisclosureGroup` with no idle
  `TimelineView` or poll timer, so idle CPU stays near zero. Native keyboard
  activation and VoiceOver come from the disclosure control.
- R6: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Changing Notes Only, splitter behavior, or hide-idle membership.
- Replacing the two-pane Vertical Mode split.
- Any extra GitHub fetch for project size or commit count. Issue #102 lists
  extra GitHub fetches as a non-goal, so no size pipeline is added.

Observable acceptance:

- Vertical Mode titles are readable on their own line; `ready` stays cyan
  and unwrapped.
- Project work is marked by a thin lantern, not a filled card.
- Hidden idle projects collapse into a `watching the quiet ones` disclosure
  list below the open work; expanding it reveals their headings.
- Hover cards, pins, review toggles, and GitHub buttons still work.

## ACCEPTED PLAN

1. Use the compact stack whenever `compact` is true, and show the
   repository label on that stack only for pinned mixed rows.
2. Mark Pinned and each project section with a thin lantern. Light it cyan
   only for running or failing work. In compact layout, wait to show
   Pulls/Actions until the heading is hovered.
3. When hide-idle is on in compact Vertical Mode, collect the hidden idle
   sections and present them in a native `DisclosureGroup` captioned
   `watching the quiet ones` below the open work, collapsed by default.
   Reuse the inline project-section stage for each hidden heading. Keep the
   stacked layout unchanged so its leftover height stays with notes.
4. Fade drag handles, unpinned pins, and empty review boxes at rest. Cover
   layout, hide-idle membership, hidden-section complement, stacked lantern
   padding, and the collapsible-list caption with tests.

## SUPERSEDED PLAN

- An earlier pass filled leftover Vertical Mode height with a ☀️ and one
  orbit of named ⭐️/🌕/🌍/🪐 bodies sized from a GitHub-backed commit-count
  cache, with revolve/spin/tug-and-spring animation. It was removed in favor
  of a standard collapsible list, and the commit-count pipeline
  (`internal/prindex` client, policy, scan, cache fields, model field, and
  projection) was deleted because extra GitHub fetches are a non-goal of
  issue #102.

## DECISIONS

- Supersede 0028's one-line unpinned Vertical Mode rows. `ready` remains a
  whole word because it lives on the identity line of the two-line stack,
  not because the title is forced to share that line.
- Hidden idle projects are a presentation of projects already hidden by 0032
  hide-idle. They live in a collapsed disclosure list below the open work,
  not in the main list, so the open work stays scannable while the quiet
  projects remain one expand away.
- A standard `DisclosureGroup` was chosen over the earlier leftover orbit:
  it scrolls with the list, gives native keyboard activation and VoiceOver,
  needs no idle animation ticks, and needs no commit-count sizing data. The
  orbit read as whimsical decoration and pulled in a GitHub commit-count
  fetch that issue #102 explicitly excludes.
- Filled rounded stages made Vertical Mode look like a dashboard. A thin
  lantern chunks the list without boxing every heading, chip, and button.
- The GitHub commit-count pipeline (client, quota policy, daily-TTL scan,
  cache fields, model field, projection) only existed to size the orbit
  bodies. Removing the orbit removed its only consumer, so the whole pipeline
  was deleted rather than left as dead, out-of-scope data.

## DISCOVERIES

- Presenting hidden idle projects inline as a native `DisclosureGroup` reuses
  the existing project-section stage, so an idle heading looks the same
  whether it is shown inline (eye off) or inside the collapsed list (eye on).
- The hidden set is the exact complement of the visible set under the same
  hide-idle filter, so `HyperliteOpenPRProjectFilter.hiddenSections` and
  `visibleSections` partition the project sections and stay in sync.
- The earlier leftover orbit needed the ScrollView content measured with
  `fixedSize` and clipped `.position()` bodies to avoid covering running
  Actions chips. Dropping the orbit for a list removed that measurement,
  the clip, and the z-order juggling entirely.

## VALIDATION

- `make macos-test` passed: full app typecheck plus the Swift model tests,
  including two-line compact rows, lantern stage kinds, drag-chrome opacity,
  hidden-section complement, and the collapsible-list caption.
- `go test ./...` and `go vet ./...` passed after removing the commit-count
  client, policy, scan, cache fields, model field, and projection.
- `make macos-build` produced `build/Hyperlite.app`. Native screenshot
  evidence is SKIPPED (ScreenCaptureKit).

## OUTCOME

- Vertical Mode Open PRs is quieter and readable: lantern-marked clusters,
  two-line titles, muted resting drag chrome, and hidden idle projects in a
  standard collapsible `watching the quiet ones` list. The leftover orbit and
  its GitHub commit-count sizing pipeline were removed. Ready pull-request
  delivery through issue #102.

## REPOSITORY MEMORY

- Feature rationale lives in this spec, including the superseded orbit plan.
  USER_GUIDE and testing.md record the operator-visible stages, two-line
  compact rows, and the collapsible hidden-project list. The Constitution no
  longer records a commit-count size fetch, because that pipeline was removed.
