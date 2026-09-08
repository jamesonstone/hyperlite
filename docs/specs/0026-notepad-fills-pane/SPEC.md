---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0026"
  slug: notepad-fills-pane
  dir: 0026-notepad-fills-pane
references:
  - id: issue-83
    name: Let Notepad fill leftover pane width
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/83
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: readable-workspace-layout
    name: Readable Workspace Layout
    type: specification
    target: docs/specs/0025-readable-workspace-layout/SPEC.md
    relation: constrains
    read_policy: must
    used_for: keep stacked fit, Vertical Mode, splitter, and Notes Only
    status: active
  - id: notepad-daily-notes
    name: Notepad And Daily Notes
    type: specification
    target: docs/specs/0006-notepad-daily-notes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: plain-text notepad remains the editor
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: notepad surface owns editor width
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

# Notepad Fills Pane

## PURPOSE

Let Notepad/Daily use the leftover pane width so the editor and header share
one surface instead of leaving a large empty gutter beside wrapped text.

## CONTEXT

Feature 0025 capped the editor at an 80-column measure so unused width would
read as margin. After stacked Open PRs shrank, leftover pane width is large.
The header already spans the pane; the capped body looks unused, not like a
book measure.

The `NSTextView` already wraps to its proposed width
(`widthTracksTextView`). The cap is a SwiftUI `maxWidth` on
`editorSurface`, not a wrapping bug in the text view.

Orchestration: single-lane, because the editor frame, the unused measure
helper, tests, and the 0025 supersession share one layout contract.

## REQUIREMENTS

- R1: The notepad editor surface fills the notepad pane horizontally.
- R2: The notepad header and editor share the same pane width.
- R3: Stacked Open PRs stay content-sized, Vertical Mode stays 36% by default,
  and Notes Only / splitter behavior is unchanged.
- R4: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Markdown preview or a second editor renderer.
- Changing stacked Open PR height or Vertical Mode default width.
- Extra GitHub fetches, timers, or helper processes.

Observable acceptance:

- There is no large empty gutter beside notepad text.
- Note text wraps to the current notepad pane width.
- Existing 0025 split, Notes Only, and title-first row behavior remains.

## ACCEPTED PLAN

1. Remove the 80-column `maxWidth` on `HyperliteNotepadView.editorSurface`.
2. Delete `notepadMeasureWidth` and its unused column constants.
3. Keep Notes Only summary tests; drop the 80-column measure assertion.
4. Record that feature 0025 R6 is superseded, and update the user guide.

## DECISIONS

- Drop the 80-column measure instead of raising it. A higher cap would still
  leave a gutter on a wide leftover pane after stacked Open PRs shrank.
- Keep the existing `NSTextView` wrap (`widthTracksTextView`). The empty
  gutter was a SwiftUI `maxWidth` on `editorSurface`, not a wrapping bug.
- Leave stacked fit-content, Vertical Mode 36%, splitter, and Notes Only
  unchanged.

## DISCOVERIES

- `kit spec notepad-fills-pane` rewrote `docs/PROJECT_PROGRESS_SUMMARY.md`
  wholesale. Restored the index and added only the 0026 row and summary.

## VALIDATION

- `make macos-test` PASS: type-check plus executable tests, including Notes
  Only summary without an 80-column measure assertion.
- `make macos-build` PASS: `build/Hyperlite.app`.
- `make fmt-check` PASS.
- `kit check --project` PASS.
- Source-file-size audit: edited source and test files are 237, 199, and 192
  lines.
- Interactive packaged-app walkthrough SKIPPED.

## OUTCOME

Notepad/Daily wraps to leftover pane width. The 80-column editor cap and its
helpers are gone. Feature 0025 split, Notes Only, and title-first rows are
unchanged. Docs describe pane-fill wrapping; 0025 R6 is superseded here.

## REPOSITORY MEMORY

- Decision: created
- Rationale: Superseding 0025's 80-column measure is a product decision that
  code and tests cannot fully preserve, including why a higher cap was
  rejected.
- Artifacts: `docs/specs/0026-notepad-fills-pane/SPEC.md`,
  `docs/specs/0025-readable-workspace-layout/SPEC.md`, `docs/USER_GUIDE.md`,
  `docs/references/testing.md`, `docs/PROJECT_PROGRESS_SUMMARY.md`
