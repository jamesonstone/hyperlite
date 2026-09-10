---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0027"
  slug: open-pr-project-sections
  dir: 0027-open-pr-project-sections
references:
  - id: issue-86
    name: Group Open PRs into project sections
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/86
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-workspace-scanability
    name: Open PR Workspace Scanability
    type: specification
    target: docs/specs/0019-open-pr-workspace-scanability/SPEC.md
    relation: constrains
    read_policy: must
    used_for: pinned section, local pin order, no extra GitHub fetches
    status: active
  - id: readable-workspace-layout
    name: Readable Workspace Layout
    type: specification
    target: docs/specs/0025-readable-workspace-layout/SPEC.md
    relation: constrains
    read_policy: must
    used_for: title-first rows, stacked height estimate, Vertical Mode compact rows
    status: active
  - id: open-pull-requests
    name: Configured Project Pull Requests
    type: specification
    target: docs/specs/0004-open-pull-requests/SPEC.md
    relation: constrains
    read_policy: must
    used_for: cached-first Open PR projection
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Open PR presentation grouping
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

# Open PR Project Sections

## PURPOSE

Make it obvious which project an Open PR belongs to by grouping unpinned rows
under prominent repository section headers instead of repeating a muted
repository label on every row.

## CONTEXT

Feature 0025 made titles the primary scanned text and muted per-row repository
identity. In Vertical Mode that identity shares the first line with number,
ready/draft, and review count, so several PRs from the same repository still
read as a flat list.

The operator asked to make the project name more prominent, and to use project
sections if that is more readable. Grouping is more readable than enlarging the
per-row label: the name appears once, at heading weight, and titles keep the
row.

Pinned stays a mixed operator-ordered list. Those rows can come from more than
one repository, so they still show repository identity.

Orchestration: single-lane, because Open PR panel composition, row content,
pinning order, and stacked height estimates share one presentation contract.

## REQUIREMENTS

- R1: Group unpinned Open PRs by repository. Each group has a prominent
  heading (semibold body size, secondary text) and a muted count.
- R2: Rows inside a project section omit the repository label. Titles remain
  the primary scanned text. Number, ready/draft, conflict, review count, and
  age stay on the row.
- R3: Keep Pinned above project sections. Pinned rows stay mixed and still
  show repository identity. An empty Pinned section remains visible as a drop
  target.
- R4: Drag and keyboard move still pin and unpin. Within a project, they
  reorder that project's rows. Across projects, they move the whole project
  group. No extra GitHub fetches.
- R5: Cached/unavailable availability rows stay below the grouped list and
  remain repository-first.
- R6: Stacked fit-content height includes one header per project section.
- R7: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Extra GitHub API calls.
- Restoring Open PR header sort, filter, hide-drafts, or copy-prompt chrome.
- Grouping the Pinned section by project.
- Collapsing an empty Pinned section.

Observable acceptance:

- Two unpinned PRs from the same repository appear under one project heading.
- The heading is visually stronger than the previous muted compact repo label.
- Rows under that heading do not repeat `owner/repo`.
- Pinned remains first; dragging into it pins a single row.
- A short stacked list still sizes to content.

## ACCEPTED PLAN

1. Group unpinned rows by `repository` in first-seen order, preserving relative
   order inside each group.
2. Replace the generic `Open N` header with project section headers when any
   unpinned rows exist.
3. Hide per-row repository identity unless the row is pinned. Vertical Mode
   two-line compact stacks remain only for pinned mixed rows.
4. Make pin-store moves repository-aware: same repo reorders inside the group;
   different repo moves the group; pin boundary stays row-level.
5. Count project headers in the stacked height estimate.
6. Cover grouping, section-aware move, and stacked height with Swift tests.

## DECISIONS

- Group unpinned rows instead of enlarging the per-row repository label.
  Repeating a louder name on every row still hides which PRs share a project.
- Do not group Pinned. Pin order is an operator-chosen mixed list; repository
  identity stays on those rows.
- Cross-project unpinned drag moves the whole project group rather than
  interleaving rows that grouping would immediately reassemble.
- Feature 0025's two-line Vertical Mode rows stay for pinned mixed rows only.
  Project-section rows are one line because the repository already lives in
  the heading.

## DISCOVERIES

- `kit spec open-pr-project-sections` rewrote `docs/PROJECT_PROGRESS_SUMMARY.md`
  wholesale. Restored the curated index and added only the 0027 row and summary.
- Pin-store moves need the row repository map. Empty maps keep the previous
  flat ID-list behavior so existing pin tests stay valid.
- Adjacent downward group drops were a no-op because insert-before after
  removal restored the original index. Adjacent-next now places the group
  after the target, matching keyboard group swap; later targets still insert
  immediately before the drop target.
- Stacked fit-content height now counts every `LazyVStack` child, including
  empty pin drop targets, PR rows, and availability rows.

## VALIDATION

- `make macos-test` PASS: type-check plus executable tests, including unpinned
  grouping, same-project reorder, cross-project group move, keyboard group
  move, pin-boundary move, and stacked height with project section counts.
- `make macos-build` PASS: `build/Hyperlite.app`.
- `make fmt-check` PASS.
- `kit check --project` PASS.
- Source-file-size audit: edited source and test files are at or under 300
  lines (`HyperlitePullRequestPinning.swift` 280,
  `HyperlitePullRequestRows.swift` 236, pinning tests 182).
- Interactive packaged-app walkthrough SKIPPED pending operator open of the
  rebuilt app.

## OUTCOME

Unpinned Open PRs group under semibold repository headings with a muted count.
Rows inside a section omit the repository label. Pinned stays a mixed list
with per-row repository identity. Drag and keyboard move stay row-level at
the pin boundary and move whole project groups across repositories.

## REPOSITORY MEMORY

- Decision: created
- Rationale: Grouping unpinned Open PRs by repository is a product scanability
  choice that code cannot preserve alone, including why Pinned stays mixed and
  why per-row labels were not merely enlarged.
- Artifacts: `docs/specs/0027-open-pr-project-sections/SPEC.md`,
  `docs/CONSTITUTION.md`, `docs/USER_GUIDE.md`, `docs/references/testing.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`,
  `docs/specs/0025-readable-workspace-layout/SPEC.md`
