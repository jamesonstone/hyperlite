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
    used_for: leftover sky has no idle TimelineView; drag return is one Core Animation spring
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
project clusters, two-line titles, and leftover height filled with a solar
system of hidden idle projects.

## CONTEXT

The two-pane split and notes pane are the right shape. After 0032 the Open
PRs column still reads as a sparse utility list: unpinned titles share one
line with `ready`/`draft` and truncate, drag chrome competes at rest, and
hide-idle leaves a large empty well instead of using the leftover column
height. Feature 0028 kept unpinned compact rows on one line so `ready`
would not wrap; this pass keeps `ready` a whole word by moving it onto the
identity line and giving the title its own line.

Orchestration: single-lane, because stages, compact-row stacking, leftover
orbit, celestial sizing, and the commit-count cache share one presentation
contract and need continuous design judgment.

## REQUIREMENTS

- R1: Vertical Mode compact rows are two lines for pinned and unpinned
  rows. Identity (`#number`, `ready`/`draft`, conflict, review) stays on
  line one as whole words. Title plus age sit on line two. Stacked
  (non-compact) rows stay one line.
- R2: Each visible project cluster, and Pinned when it has rows, is marked
  by a thin left lantern. Running or failing work lights that lantern cyan.
  No filled cards.
- R3: When hide-idle is on in Vertical Mode and leftover pane height remains,
  hidden idle projects appear in that leftover as emoji bodies on one orbit
  around a ☀️. Every hidden project is a selectable ⭐️, 🌕, 🌍, or 🪐
  sized from cached commit count, with its short name visible. Bodies
  revolve around the sun and spin in place with implicit Core Animation.
  Pull a body and it springs back to its slot, staying inside leftover;
  the sky clips draw and hit-testing so bodies cannot cover the visible
  list. Click a body to open the repository. Help keeps the idle
  availability text. Hide-idle membership does not change. Stacked
  fit-content does not grow a sky; leftover height there still goes to
  notes. No decorative leftover ghosts.
- R4: Drag handles, unpinned pins, and empty review boxes are quieter at rest
  and full on row hover. Number→issue, title→PR, Pulls/Actions, running
  chips, hover cards, and the refresh overlay stay. Compact Pulls/Actions
  wait on heading hover. Visible project headings show the same celestial
  glyph as the leftover body for that project. Running GitHub Actions
  chips keep their 12 Hz gliding 👻; leftover sky must not cover them.
- R5: Leftover sky has no idle `TimelineView` or poll timer. Revolution and
  spin use implicit Core Animation. Drag offsets a body; release returns it
  with one Core Animation spring. Reduce Motion stills revolution and spin
  and snaps bodies home with no spring.
- R6: Keep handwritten source and test files at or under 300 lines.
- R7: Commit counts are a cached pull-request-index field. Local `git
  rev-list --count HEAD` may seed a missing count. GitHub
  `history { totalCount }` may refresh a count only during an already
  authorized stale or force scan, at most once per 24 hours per
  repository, and only when the cached quota observation has excess remaining.
  The activity poll never fetches sizes. Size queries never join the hot
  pull-request query.

Non-goals:

- Changing Notes Only, splitter behavior, or hide-idle membership.
- Replacing the two-pane Vertical Mode split.
- A new automatic GitHub poll for project size.

Observable acceptance:

- Vertical Mode titles are readable on their own line; `ready` stays cyan
  and unwrapped.
- Project work is marked by a thin lantern, not a filled card.
- Hidden idle projects fill leftover Vertical Mode height as one orbit of
  named emoji bodies that revolve around a sun; pull-and-spring still works.
- Open-PR project headings show a matching size glyph.
- Hover cards, pins, review toggles, and GitHub buttons still work.

## ACCEPTED PLAN

1. Use the compact stack whenever `compact` is true, and show the
   repository label on that stack only for pinned mixed rows.
2. Mark Pinned and each project section with a thin lantern. Light it cyan
   only for running or failing work. In compact layout, wait to show
   Pulls/Actions until the heading is hovered.
3. Measure the Open PRs list against the Vertical Mode pane and, when
   leftover height remains under hide-idle, render a ☀️ plus one orbit of
   named emoji bodies that revolve, spin, and tug-and-spring. Clip the
   leftover and keep the list above it so hover and running chips stay
   live. Keep stacked height content-sized.
4. Fade drag handles, unpinned pins, and empty review boxes at rest. Cover
   layout, sky membership, one-body-per-hidden-project, celestial
   classification, orbit bounds, leftover drag clamp, stacked lantern
   padding, and commit-count cache policy with tests.
5. Seed missing counts from local git. Fetch GitHub counts in a batched
   follow-up after a successful stale or force scan when the count is older
   than 24 hours and quota remaining is excess. Never fetch sizes from the
   activity poll or the hot pull-request query.

## DECISIONS

- Supersede 0028's one-line unpinned Vertical Mode rows. `ready` remains a
  whole word because it lives on the identity line of the two-line stack,
  not because the title is forced to share that line.
- Leftover sky is presentation of projects already hidden by 0032 hide-idle.
  It does not keep those projects in the main list.
- Filled rounded stages made Vertical Mode look like a dashboard. A thin
  lantern chunks the list without boxing every heading, chip, and button.
- Wrapping `👻 name` tokens and a sunflower of unlabeled emoji-ghosts were
  both wrong: too much text, then too many ghosts with only one obvious
  hit target. One orbit around a ☀️, with a named emoji body per hidden
  project, is the space treatment.
- Body kind is absolute from commit count (star / moon / planet / giant),
  not a peer percentile, so a project's glyph stays stable when neighbors
  hide and two similar repos stay the same kind.
- A 12 Hz leftover `TimelineView` was too expensive for idle decoration.
  Revolution and spin use implicit Core Animation. Pull uses a gesture
  offset; bounce-back is one underdamped Core Animation spring on the
  released body only. Reduce Motion stills the field and snaps home.
- Commit-count GitHub access is part of an already authorized pull-request
  refresh, not a new automatic poll. Excess remaining (at least the larger
  of 2,000 points or 40% of the limit) is the quiet-period gate. The activity
  quota governor still only denies the activity poll.

## DISCOVERIES

- ScrollView children report viewport height unless the list is
  `fixedSize(horizontal: false, vertical: true)`. The leftover ghost sky
  depends on that intrinsic measure; otherwise leftover is always zero.
  `LazyVStack` still under-measures inside that ScrollView, so the
  compact panel uses a `VStack` and leftover starts only below the last
  visible row.
- Unclipped `.position()` orbit bodies drew and hit-tested into the
  visible list, stealing heading hover and covering running Actions
  chips. Leftover is clipped, the list wins z-order, drag is clamped to
  leftover, and the orbit radius scales to leftover size.
- A first pass boxed every project and labeled every hidden ghost. That
  read as busy chrome. Lanterns plus a nameless constellation were calmer
  to watch but failed association: tiny `.position()` glyphs made only
  one name (`status`) feel selectable. Named bodies with a 36pt hit
  target are the fix.
- `defaultBranchRef { target { ... on Commit { history(first: 1) {
  totalCount } } } }` is cheap, but it must not ride the five-minute
  pull-request query. Local `rev-list --count HEAD` is enough for first
  paint.
- A leftover `TimelineView` at 12 Hz rebuilt every body on the ring.
  Gesture offset plus one spring on release keeps idle CPU near zero.
  Revolution and spin stay on implicit Core Animation so SwiftUI does not
  tick the leftover sky. Decorative leftover ghosts were removed; project
  bodies use ☀️⭐️🌕🌍🪐 emoji.

## VALIDATION

- `make macos-test` passed after leftover clip, scaled orbit, drag clamp,
  list-over-sky z-order, and restoring running-chip layout priority.
- `go test ./internal/prindex/...` passed for commit-count query shape, daily
  TTL, excess-quota denial, local seed, and cache preserve on PR refresh.
- `make macos-build` produced `build/Hyperlite.app` and relaunched it.
  Native screenshot evidence is SKIPPED (ScreenCaptureKit).

## OUTCOME

- Vertical Mode Open PRs is a quieter watch stage: lantern-marked clusters,
  two-line titles, and a leftover hidden-idle solar system. Ready
  pull-request delivery through issue #102.

## REPOSITORY MEMORY

- Feature rationale lives in this spec. USER_GUIDE and testing.md record the
  operator-visible stages, two-line compact rows, leftover orbit, and
  heavily cached commit counts. Constitution records that size fetches are
  part of the pull-request index refresh, not a new automatic poll.
