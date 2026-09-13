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
    used_for: no extra timers for idle ghosts
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

Make Vertical Mode's Open PRs pane a readable watch stage: lantern-marked
project clusters, two-line titles, and leftover height filled with a slow
field of ghosts for hidden idle projects.

## CONTEXT

The two-pane split and notes pane are the right shape. After 0032 the Open
PRs column still reads as a sparse utility list: unpinned titles share one
line with `ready`/`draft` and truncate, drag chrome competes at rest, and
hide-idle leaves a large empty well instead of using the leftover column
height. Feature 0028 kept unpinned compact rows on one line so `ready`
would not wrap; this pass keeps `ready` a whole word by moving it onto the
identity line and giving the title its own line.

Orchestration: single-lane, because stages, compact-row stacking, leftover
sky, and stacked height share one presentation contract and need continuous
design judgment.

## REQUIREMENTS

- R1: Vertical Mode compact rows are two lines for pinned and unpinned
  rows. Identity (`#number`, `ready`/`draft`, conflict, review) stays on
  line one as whole words. Title plus age sit on line two. Stacked
  (non-compact) rows stay one line.
- R2: Each visible project cluster, and Pinned when it has rows, is marked
  by a thin left lantern. Running or failing work lights that lantern cyan.
  No filled cards.
- R3: When hide-idle is on in Vertical Mode and leftover pane height remains,
  hidden idle projects appear in that leftover as a slow constellation of 👻
  glyphs. Names appear on hover. Click opens the repository. Help keeps the
  idle availability text. Hide-idle membership does not change. Stacked
  fit-content does not grow a sky; leftover height there still goes to notes.
- R4: Drag handles, unpinned pins, and empty review boxes are quieter at rest
  and full on row hover. Number→issue, title→PR, Pulls/Actions, running
  chips, hover cards, and the refresh overlay stay. Compact Pulls/Actions
  wait on heading hover.
- R5: Ghost sky drift uses implicit Core Animation, not a new poll timer.
  Honor Reduce Motion by keeping ghosts still.
- R6: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Extra GitHub fetches or poll changes.
- Changing Notes Only, splitter behavior, or hide-idle membership.
- Replacing the two-pane Vertical Mode split.

Observable acceptance:

- Vertical Mode titles are readable on their own line; `ready` stays cyan
  and unwrapped.
- Project work is marked by a thin lantern, not a filled card.
- Hidden idle projects fill leftover Vertical Mode height as a slow
  clickable ghost field.
- Hover cards, pins, review toggles, and GitHub buttons still work.

## ACCEPTED PLAN

1. Use the compact stack whenever `compact` is true, and show the
   repository label on that stack only for pinned mixed rows.
2. Mark Pinned and each project section with a thin lantern. Light it cyan
   only for running or failing work. In compact layout, wait to show
   Pulls/Actions until the heading is hovered.
3. Measure the Open PRs list against the Vertical Mode pane and, when
   leftover height remains under hide-idle, render a constellation of
   drifting 👻 glyphs. Names appear on hover. Keep stacked height content-sized.
4. Fade drag handles, unpinned pins, and empty review boxes at rest. Cover
   layout, sky membership, constellation bounds, and stacked lantern
   padding with Swift tests.

## DECISIONS

- Supersede 0028's one-line unpinned Vertical Mode rows. `ready` remains a
  whole word because it lives on the identity line of the two-line stack,
  not because the title is forced to share that line.
- Ghost sky is presentation of projects already hidden by 0032 hide-idle.
  It does not keep those projects in the main list and does not add fetches.
- Filled rounded stages made Vertical Mode look like a dashboard. A thin
  lantern chunks the list without boxing every heading, chip, and button.
- Wrapping `👻 name` tokens for 18 idle projects was more text. A
  constellation of glyphs, with names on hover, is calmer and more fun to
  watch.
- Ghost sky drift uses implicit SwiftUI animation, not a TimelineView, so
  it does not add a poll-style timer. Reduce Motion keeps the field still.

## DISCOVERIES

- ScrollView children report viewport height unless the list is
  `fixedSize(horizontal: false, vertical: true)`. The leftover ghost sky
  depends on that intrinsic measure; otherwise leftover is always zero.
- A first pass boxed every project and labeled every hidden ghost. That
  read as busy chrome. Lanterns plus a nameless constellation were the calmer
  treatment that still keeps hover and click.

## VALIDATION

- `make macos-test` passed after lanterns, two-line compact rows, leftover
  ghost-sky membership, quieter rest chrome, and stacked padding.
- `make macos-build` produced `build/Hyperlite.app`.

## OUTCOME

- Vertical Mode Open PRs is a quieter watch stage: lantern-marked clusters,
  two-line titles, and a leftover hidden-idle ghost field. Ready pull-request
  delivery through issue #102.

## REPOSITORY MEMORY

- Feature rationale lives in this spec. USER_GUIDE and testing.md record the
  operator-visible stages, two-line compact rows, and leftover ghost sky.
  Constitution unchanged: hide-idle membership, notes-plus-Open-PRs native
  window, and the bounded activity-poll timer invariant are the same.
