---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0028"
  slug: open-pr-ready-inline
  dir: 0028-open-pr-ready-inline
references:
  - id: issue-88
    name: Keep Open PR ready/draft on one line
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/88
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-project-sections
    name: Open PR Project Sections
    type: specification
    target: docs/specs/0027-open-pr-project-sections/SPEC.md
    relation: constrains
    read_policy: must
    used_for: unpinned rows stay one line under the project heading
    status: active
  - id: readable-workspace-layout
    name: Readable Workspace Layout
    type: specification
    target: docs/specs/0025-readable-workspace-layout/SPEC.md
    relation: constrains
    read_policy: must
    used_for: title-first rows; two-line compact stack only for pinned mixed identity
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Open PR row presentation
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

# Open PR Ready Inline

## PURPOSE

Keep `ready` and `draft` as whole words on Open PR rows so a narrow Vertical
Mode pane never stacks those badges letter-by-letter.

## CONTEXT

Feature 0027 grouped unpinned rows under project headings and hid the per-row
repository label. Those rows stay one line. Vertical Mode still passes the
compact-row flag so pinned mixed rows can use the two-line stack.

The one-line body used unconstrained number and ready/draft labels with a
lower layout priority than the title. In a tight HStack SwiftUI gave those
labels a one-character width, so `ready`, `#415`, and long titles wrapped
vertically.

Orchestration: single-lane, because the compact-stack vs one-line choice,
metadata compression resistance, and title truncation are one presentation
contract.

## REQUIREMENTS

- R1: Number, ready/draft, review count, and conflict glyphs keep their
  intrinsic width. They do not wrap and they do not yield space before the
  title.
- R2: The title truncates with a tail ellipsis when the pane is narrow.
- R3: Unpinned project-section rows stay one line. Pinned mixed rows keep the
  two-line compact stack when they still show repository identity.
- R4: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Changing project-section grouping or pin behavior.
- Restoring per-row repository labels on unpinned rows.
- Extra GitHub fetches.

Observable acceptance:

- A long-title unpinned PR in Vertical Mode shows `ready` or `draft` as a
  whole word on the same line as `#N`.
- The title truncates instead of wrapping onto many lines.
- Pinned mixed rows still use the two-line compact stack.

## ACCEPTED PLAN

1. Keep compact-stack vs one-line selection as `compact && showRepository`.
2. Give number, ready/draft, and review count `lineLimit(1)`, horizontal
   `fixedSize`, and a higher layout priority than the title.
3. Let the title take leftover width with `minWidth: 0` so it truncates.
4. Cover the compact-stack gate and metadata-over-title priority with Swift
   tests.

## DECISIONS

- Do not return project-section rows to the two-line stack. Feature 0027 put
  repository identity in the heading; wrapping metadata is the bug, not the
  one-line layout.
- Prefer intrinsic-width metadata over a wider fixed `ready` column. A fixed
  42 pt frame still wraps when the word is wider than the frame.
- Title yields first. Age already used `fixedSize` and a high layout priority;
  number and ready/draft must match that resistance.

## DISCOVERIES

- `kit spec open-pr-ready-inline` rewrote `docs/PROJECT_PROGRESS_SUMMARY.md`
  wholesale. Restored the curated index and added only the 0028 row and
  summary.
- One-line Vertical Mode rows still received `compact == true`, so the merge-
  conflict glyph skipped the reserved column and shifted title/age when a
  conflict was present. Conflict sizing now follows `usesCompactStack`.

## VALIDATION

- `make macos-test` PASS: type-check plus executable tests, including compact
  vs one-line selection, metadata layout priority, and reserved conflict
  width on one-line rows.
- Source-file-size audit: edited source and test files are 178, 298, and 253
  lines.
- Interactive packaged-app walkthrough SKIPPED.

## OUTCOME

Unpinned project-section rows stay one line. Number, `ready`/`draft`, and
review count keep intrinsic width so they cannot wrap letter-by-letter; the
title truncates. One-line rows reserve aligned conflict width. Pinned mixed
rows still use the two-line compact stack.

## REPOSITORY MEMORY

Created `docs/specs/0028-open-pr-ready-inline/SPEC.md` for the one-line
metadata contract. Constitution unchanged: this is feature-local presentation,
not a new project-wide invariant. User guide and testing reference updated.
