---
kit_metadata_version: 1
artifact: "spec"
workflow_version: 2
phase: "deliver"
clarification:
  status: "ready"
  confidence: 100
  unresolved_questions: 0
feature:
  id: "0008"
  slug: "dashboard-list-organization"
  dir: "0008-dashboard-list-organization"
references:
  - id: "issue-35"
    name: "Add dashboard list organization controls"
    type: "github-issue"
    target: "https://github.com/jamesonstone/hyperlite/issues/35"
    relation: "implements"
    read_policy: "must"
    used_for: "product scope and acceptance criteria"
    status: "active"
  - id: "open-pull-requests"
    name: "Configured Project Pull Requests"
    type: "specification"
    target: "docs/specs/0004-open-pull-requests/SPEC.md"
    relation: "informs"
    read_policy: "must"
    used_for: "cached-first pull-request projection and row contracts"
    status: "active"
  - id: "dashboard-project-management"
    name: "Dashboard And Project Management"
    type: "specification"
    target: "docs/specs/0005-dashboard-project-management/SPEC.md"
    relation: "informs"
    read_policy: "must"
    used_for: "equal-section layout and configured-project behavior"
    status: "active"
  - id: "frontend-architecture"
    name: "Frontend Application Architecture"
    type: "ruleset"
    target: "docs/references/rules/frontend-application-architecture.md"
    relation: "constrains"
    read_policy: "must"
    used_for: "presentation, interaction-state, and persistence ownership"
    status: "active"
  - id: "testing"
    name: "Testing And Environment Validation"
    type: "ruleset"
    target: "docs/references/rules/testing-and-environment-validation.md"
    relation: "constrains"
    read_policy: "must"
    used_for: "focused model, native build, and packaged-app evidence"
    status: "active"
---
# Dashboard List Organization

## THESIS

Hyperlite should let operators quickly reduce, prioritize, and arrange the dense
Open PRs and Projects lists without turning either title bar into a prominent
toolbar. Each section should expose quiet, accessible controls on its existing
header line, while preserving read-only GitHub and project-index authority.

## CONTEXT

Open PRs currently flattens every configured repository into a deterministic
recent-first list. Projects renders configured checkouts in configuration order
and expands every visible branch and worktree lane. Both projections are native
SwiftUI presentation over cached read-only data; neither needs another GitHub
query, filesystem scan, or configuration write to organize the current view.

The project configuration writer deliberately sorts selected paths. Manual
dashboard order is therefore a local presentation preference rather than a
change to canonical project configuration. Pull requests are dynamic, so their
stable repository/project plus PR identity must anchor custom order while new
rows remain visible and closed rows may disappear without corrupting settings.

## CLARIFICATIONS

- The user accepted the recommended always-visible muted header controls.
- Reordering uses an explicit mode with drag handles, Done/Cancel semantics,
  and accessible move actions instead of a long-press gesture.
- Project collapse is available per project and through a header-level toggle.
- Filtering is local to the loaded projections and never initiates refresh work.
- Sort, committed custom order, and collapse state persist locally; filter text
  and filter selections are transient so a prior investigative view does not
  unexpectedly hide data on a later launch.

## REQUIREMENTS

- R1: Add compact filter, sort, and reorder controls to the Open PRs header and
  collapse-all, filter, sort, and reorder controls to the Projects header.
- R2: Keep controls visible, muted, keyboard reachable, fully labeled for
  accessibility, and highlighted with the existing cyan accent only while
  active. Preserve the current freshness and Projects context labels.
- R3: Filter Open PRs by case-insensitive repository/title/number text,
  repository, ready/draft state, review status, and current/cached/unavailable
  data status. Show a filtered count without changing the source projection.
- R4: Sort Open PRs by recent update, repository, review attention, ready/draft
  state, PR number, or custom order. Preserve recent-first as the default.
- R5: Filter Projects by case-insensitive project/repository/path/branch text,
  branch or worktree lane, and active-worktree or open-PR presence. When a lane
  matches, retain its project context and only matching lanes where practical.
- R6: Sort Projects by configured order, name, active worktree count, open PR
  count, or custom order. Preserve configured order as the default.
- R7: Let each project collapse to its identity and primary-branch summary.
  Collapse/expand-all acts on the currently presented projects. Active filters
  temporarily expand matching projects without erasing saved collapse state.
- R8: Entering reorder mode displays the complete source list, suspends filter
  and non-custom sort presentation, disables row navigation, and exposes drag
  handles. Done commits order and selects Custom; Cancel restores the prior
  sort and order exactly.
- R9: Persist committed custom orders, selected sorts, and collapsed project IDs
  in app-local preferences. Never mutate Hyperlite configuration, repositories,
  pull requests, or cached scan records.
- R10: Newly observed PRs appear before previously arranged custom rows so they
  are not hidden by a stale priority list. Newly configured projects append to
  a custom project order. Unknown saved identifiers remain harmless.
- R11: Preserve macOS 13 support, existing typography/theme tokens, equal panel
  sizing, cached-first PR freshness, PR URL opening, and no-continuous-work
  behavior.

Non-goals: server-side GitHub filtering, changing scan frequency, editing PRs,
writing project configuration order, deleting rows, adding a new settings page,
or making the dashboard a general table component.

## ASSUMPTIONS

- Stable existing project and pull-request identifiers are sufficient for
  presentation preference keys.
- App-local UserDefaults is the existing appropriate boundary for durable
  presentation preferences; scan and configuration stores remain authoritative
  for data existence and liveness.
- The existing equal-height independent ScrollViews continue owning overflow.

## ACCEPTANCE CRITERIA

- AC1: Both headers expose the requested controls on their existing title line
  without displacing the freshness/context label at normal window width.
- AC2: Every Open PR filter and sort produces deterministic rows from the same
  loaded scan and clear filter state restores the unfiltered source projection.
- AC3: Every Project filter and sort is deterministic; lane matches preserve a
  recognizable project parent and filtering performs no external work.
- AC4: Individual and collapse-all actions hide subordinate project lanes;
  filtering expands matches temporarily and clearing filters restores collapse.
- AC5: Dragging or invoking accessible move actions changes only reorder drafts;
  Cancel restores prior state and Done persists Custom order across re-creation.
- AC6: PR rows cannot open while reorder mode is active, while ordinary rows
  continue opening their existing GitHub URLs.
- AC7: Stale preference identifiers do not remove current rows. A newly observed
  PR leads custom order and a newly configured project follows saved projects.
- AC8: Focused model tests, native type-check/tests, universal packaged build,
  code signing, architecture inspection, and packaged-app interaction pass.

## IMPLEMENTATION PLAN

1. Add framework-independent filter/sort/custom-order presentation models for
   Open PR and Project projections.
2. Add one dashboard organization state owner for transient filters, persisted
   sorts/collapse/order, and transactional reorder drafts.
3. Add reusable compact header icons, filter popovers, and a drag/drop delegate.
4. Integrate organization state into Open PRs and Projects without moving data
   fetching or persistence into reusable row components.
5. Add deterministic tests for every filter/sort, new/stale identity behavior,
   collapse persistence, and reorder Done/Cancel transitions.
6. Validate the full app and inspect the packaged UI, accessibility tree, and
   representative sorting/filtering/collapse/reorder journeys.

Rollback removes the presentation state, controls, and tests; the underlying
read-only scans and project configuration remain unchanged.

## TASK CHECKLIST

- [x] Reconcile scope, existing projections, and delivery lane.
- [x] Capture accepted UX and persistence boundaries before source edits.
- [x] Implement presentation models and local organization state.
- [x] Integrate compact controls, collapse, filtering, sorting, and reordering.
- [x] Add focused deterministic tests.
- [x] Complete native and packaged-app validation.
- [x] Curate repository memory for ready pull-request delivery.

## VALIDATION MAP

- AC1, AC4, AC6: packaged-app screenshots, accessibility inspection, and direct
  pointer/keyboard interaction.
- AC2, AC3, AC5, AC7: executable Swift presentation/state tests.
- AC8: `make fmt-check vet test test-race build macos-test macos-build`,
  `kit check --all`, strict deep code-sign verification, and `lipo` inspection.

## REFLECTION NOTES

- A single main-actor organization state keeps transient filters separate from
  durable preferences and allows both panels to share transactional reorder
  semantics without taking ownership of either source projection.
- Reorder mode deliberately replaces navigable PR rows with non-navigating
  rows. Drag handles remain visually quiet, while named Move up/Move down
  actions make the same operation available through accessibility clients.
- Project filters temporarily override collapse presentation rather than
  mutating saved collapse IDs, so investigation never destroys the operator's
  spatial setup.
- Custom normalization keeps unknown saved IDs harmless, leads with newly
  observed PRs, and appends newly configured projects.
- Packaged-app review caught and removed normal-mode project move actions from
  the accessibility tree before final validation.

## DOCUMENTATION UPDATES

- This specification records the accepted behavior and validation evidence.
- `docs/USER_GUIDE.md` documents title-line controls, persistence, filtering,
  collapse, and reorder Done/Cancel behavior.
- `docs/CONSTITUTION.md` now distinguishes the stable configured-project source
  projection from temporary local filtering and collapse presentation.
- `docs/PROJECT_PROGRESS_SUMMARY.md` indexes the delivered feature.

## DELIVERY DECISION

Issue #35 is assigned to Jameson Stone. Implementation uses branch `GH-35` in
the canonical writable worktree and will be delivered as a ready pull request
after explicit staging, human-identity verification, and complete validation.

## EVIDENCE

Pre-implementation recon confirmed a clean root `main`, exact equality with the
freshly fetched `origin/main`, no matching issue/branch/PR, the human GitHub and
git identity, and a clean `GH-35` worktree based at
`8f345c596b237e43c845f956c675f8720df127c5`.

Focused Swift tests exercise PR and Project filtering, every sort family,
custom-order normalization, persisted sort/collapse state, and reorder
Done/Cancel transitions. `make macos-test` passes.

The complete `make fmt-check vet test test-race build macos-test macos-build`
gate passes. The only Swift diagnostics are the three pre-existing macOS 14
`onChange(of:perform:)` deprecation warnings in `HyperlitePaletteViews.swift`.
`kit check --all` passes all eight features, and `git diff --check` plus a
changed-file secret-marker scan pass. Strict deep code-sign verification passes;
both packaged executables contain `x86_64` and `arm64` slices.

Packaged-app interaction at the current loaded data set verified same-line
controls, filtered counts and empty state, PR and Project sort choices, project
collapse and filter-time expansion restoration, transactional Cancel behavior,
drag-handle presentation, accessible moves during reorder, normal row
button presentation outside reorder, and removal of move actions outside reorder
mode.
The final dashboard screenshot is stored as local delivery evidence at
`/Users/jamesonstone/.codex/visualizations/2026/08/04/019fcd0a-08ab-73c2-9516-2cd5919611fb/hyperlite-dashboard-list-controls.png`.

`kit reconcile --all --output-only` confirms all new source and test files are
below 300 physical lines. It also reports six unrelated pre-existing oversized
files and instruction-refresh warnings; those baseline findings remain outside
issue #35.
