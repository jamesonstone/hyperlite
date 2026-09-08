---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0025"
  slug: readable-workspace-layout
  dir: 0025-readable-workspace-layout
references:
  - id: issue-81
    name: Make workspace layout readable, notes-first, and resizable
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/81
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: pr-first-workspace-layout
    name: PR-First Workspace Layout
    type: specification
    target: docs/specs/0022-pr-first-workspace-layout/SPEC.md
    relation: constrains
    read_policy: must
    used_for: stacked default and Command-K Vertical Mode
    status: active
  - id: lean-native-window
    name: Lean Native Window
    type: specification
    target: docs/specs/0017-lean-native-window/SPEC.md
    relation: constrains
    read_policy: must
    used_for: notes and Open PRs as the only native surfaces
    status: active
  - id: runtime-resource-cut
    name: Runtime Resource Cut
    type: specification
    target: docs/specs/0018-runtime-resource-cut/SPEC.md
    relation: constrains
    read_policy: must
    used_for: no extra timers, helpers, or launch work
    status: active
  - id: notepad-daily-notes
    name: Notepad And Daily Notes
    type: specification
    target: docs/specs/0006-notepad-daily-notes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: plain-text notepad remains the editor
    status: active
  - id: command-palettes
    name: Performant Command Palettes And Diagnostics
    type: specification
    target: docs/specs/0002-command-palettes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: Command-K-only Notes Only toggle
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: window layout and appearance persistence
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

# Readable Workspace Layout

## PURPOSE

Make the native window readable and notes-first: Open PRs take only the space
they need, Vertical Mode keeps titles readable, the operator can drag and
collapse the split, and leftover height goes to notes. Feature 0026
supersedes the 80-column notepad measure.

## CONTEXT

Stacked and Vertical Mode currently share leftover space equally. A short Open
PRs list leaves a dead pane, while a long daily note is cramped or stretched
into a newspaper column. Narrow Vertical Mode truncates titles. Feature 0022
deferred drag-resize splitters.

Hyperlite must stay idle: no extra GitHub work, timers, markdown renderer, or
per-row geometry.

Orchestration: single-lane, because window composition, appearance, Open PR
rows, and notepad width share one tightly coupled layout contract.

## REQUIREMENTS

- R1: Stacked default sizes Open PRs to content, capped at 48% of the content
  area, and gives leftover height to Notepad/Daily.
- R2: Vertical Mode defaults Open PRs to 36% width, not half.
- R3: A draggable divider persists stacked and left-right ratios separately.
  Double-click restores that layout's default. Persist on drag end only.
- R4: Command-K Notes Only hides Open PR rows, shows `Open PRs N · Pinned N`,
  and gives the editor the rest of the window. The summary expands the list.
  The choice persists locally.
- R5: Vertical Mode uses two-line Open PR rows. Stacked wide rows stay one
  line. Titles are the primary text; repository identity is muted; age sits
  beside the title instead of a far-right gutter.
- R6: Superseded by feature 0026. Originally wrapped near 80 monospaced
  columns, left-aligned; the cap left a large empty gutter.
- R7: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Markdown preview or a second editor renderer.
- Header layout controls, Settings split controls, or keyboard PR-row loops.
- Collapsing an empty Pinned section.
- Extra GitHub fetches, timers, or helper processes.

Observable acceptance:

- A short Open PRs list does not split a tall stacked window in half.
- Vertical Mode shows two-line rows and a narrower-than-half PR pane.
- Dragged ratios survive relaunch; double-click restores the default.
- Notes Only hides rows and expands from the summary or Command-K.
- Note text wrapping is owned by feature 0026 (fills leftover pane width).

## ACCEPTED PLAN

1. Persist `notesOnly`, `stackedSplitFraction` (`0` = fit content), and
   `verticalSplitFraction` on `HyperliteAppearance`.
2. Compose a one-workspace GeometryReader, content-sized stacked split, 36%
   default vertical split, and a drag-end splitter.
3. Skip rendering Open PR rows while Notes Only is on.
4. Pass a compact-row flag from arrangement, not per-row geometry.
5. Feature 0026 removed the 80-column editor cap so notes fill leftover pane
   width.
6. Cover split math, persistence, Notes Only, compact rows, and title-first
   layout with executable Swift tests.

## DECISIONS

- Feature 0022's "no drag-resize splitters" non-goal is superseded here.
- Markdown preview stays out: it would add a renderer and fight the
  plain-text notepad contract and idle-resource cut.
- Compact rows follow Vertical Mode, not a live width threshold, so rows do
  not own GeometryReaders.
- Splitter writes UserDefaults on drag end only.
- Stacked fit-content height is estimated from row counts so `LazyVStack` can
  stay lazy. Measuring the list with `fixedSize` would layout every row.
- Tiny stacked drags snap back to fit-content so a short list does not jump
  to the 18% minimum pane. Double-click reset takes gesture priority over drag.
- Compact Vertical Mode titles stay one truncated line so the row is exactly
  two lines: identity, then title plus age. Age uses intrinsic width so the
  title truncates first.
- Compact metadata columns drop their wide-row reserved widths so a dragged
  18% Vertical Mode pane can truncate instead of clipping. The splitter is an
  adjustable VoiceOver control.
- Feature 0026 supersedes the 80-column notepad measure. After stacked Open
  PRs shrank, leftover pane width made the cap look like unused space.

## DISCOVERIES

- UserDefaults `object(forKey:)` is required for the vertical split default.
  A missing double would otherwise decode as `0` and look like fit-content.
- Markdown preview stayed out: a second renderer would fight the plain-text
  notepad contract and the idle-resource cut.
- A GeometryReader behind a vertically `fixedSize` Open PRs stack would report
  content height, but it also forces every lazy row to layout. Row-count
  estimates keep idle layout cheap.

## VALIDATION

- `make macos-test` PASS: stacked fit/cap and row-count estimate, 36% vertical
  default, drag clamp, tiny stacked-drag snap-back to fit-content, Notes Only
  and split persistence, Command-K Notes Only, title-first Open PR rows,
  and availability rows remaining repository-first.
- `make macos-build` PASS: `build/Hyperlite.app`.
- `make fmt-check` PASS.
- `kit check --project` PASS.
- Source-file-size audit: no version-control-eligible handwritten source or
  test file exceeds 300 lines.
- Interactive packaged-app walkthrough SKIPPED.

## OUTCOME

Stacked Open PRs size to a row-count estimate, capped at 48% of the content
area, and leftover height goes to notes. Vertical Mode defaults to 36% width
and two-line title-first rows. A drag-end splitter persists stacked and
left-right ratios separately; double-click restores that layout's default.
Command-K Notes Only hides Open PR rows and shows `Open PRs N · Pinned N`.
Notepad width is owned by feature 0026. Open PR `LazyVStack` stays lazy; UserDefaults
writes happen on mouse-up only. Markdown preview stayed out.

## REPOSITORY MEMORY

- Decision: created
- Rationale: Independent split ratios, Notes Only, the 0022 splitter
  supersession, and the lazy row-count estimate are material decisions that
  code and tests cannot fully preserve.
- Artifacts: `docs/specs/0025-readable-workspace-layout/SPEC.md`,
  `docs/CONSTITUTION.md`, `docs/USER_GUIDE.md`, `docs/references/testing.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`
