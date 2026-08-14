---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0010"
  slug: notes-pinboard
  dir: 0010-notes-pinboard
references:
  - id: issue-41
    name: Add bounded spatial notes pinboard
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/41
    relation: implements
    read_policy: must
    used_for: product scope and observable acceptance
    status: active
  - id: dashboard-project-management
    name: Dashboard And Project Management
    type: specification
    target: docs/specs/0005-dashboard-project-management/SPEC.md
    relation: constrains
    read_policy: must
    used_for: shared header, dashboard preservation, and command palette behavior
    status: active
  - id: notepad-daily-notes
    name: Notepad Daily Notes
    type: specification
    target: docs/specs/0006-notepad-daily-notes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: private Markdown authority, bounded storage, and note separation
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: workspace, state, interaction, and component ownership
    status: active
  - id: backend-architecture
    name: Backend Service Architecture
    type: ruleset
    target: docs/references/rules/backend-service-architecture.md
    relation: constrains
    read_policy: must
    used_for: Go storage authority and narrow helper boundary
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: focused, complete, and packaged-app evidence
    status: active
skills: []
---

# Notes Pinboard

## PURPOSE

Hyperlite should provide one private, bounded spatial Pinboard for arranging
plain notes inside titled sections without changing the current Dashboard or
turning graphical working memory into project, task, agent, or lifecycle state.

## CONTEXT

The current native window dedicates the complete content area beneath its
shared header to equal-height Notes, Open PRs, and Projects sections. That
Dashboard is intentionally compact and evidence-oriented; squeezing another
panel into it would reduce the usefulness of every existing surface.

Pinned and daily notes already establish Hyperlite's private app-data
conventions: Go owns bounded, validated, user-only atomic Markdown persistence,
while Swift owns responsive presentation through narrow helper calls. A
spatial board needs the same authority boundary while separating content
recency from layout motion. Dragging a note or section must never rewrite note
content or imply that an old note was recently edited.

The requested surface is deliberately smaller than a Kanban system or canvas
editor. It has one finite global board, movable rectangular sections, freely
positioned notes, explicit editing, forking, and recoverable archive. It has no
workflow lanes, repository semantics, automation, semantic graph, or external
coordination role.

## REQUIREMENTS

- R1: Preserve the current Dashboard and every existing Notes, Open PR,
  Projects, pinned Codex, refresh, settings, palette, and no-continuous-work
  behavior. Add Pinboard as a second full-content workspace beneath the same
  stable header, never as a fourth Dashboard section.
- R2: Put an always-visible, keyboard-reachable Dashboard/Pinboard segmented
  icon switch immediately beside the Hyperlite title. Command-1 shows
  Dashboard and Command-2 shows Pinboard while Hyperlite is focused.
- R3: Add deterministic Command-K entries for Show Dashboard, Show Pinboard,
  Add Pinboard Note, Add Pinboard Section, and Open Pinboard Archive. Preserve
  current palette search, dismissal, focus, and keyboard navigation.
- R4: Provide one finite global board. Use bounded two-axis native scrolling
  only when the board exceeds the viewport; do not add zoom, rotation, lasso,
  connectors, drawing, nested canvases, auto-layout, or infinite expansion.
- R5: Model sections as opaque stable IDs with a trimmed nonempty title and a
  rectangular frame. Sections can be created, renamed, moved, resized within
  conservative board bounds, and deleted only through explicit safe rules.
  Renaming never changes section identity or note membership.
- R6: Model each note with one opaque stable ID, exactly one section, a
  section-relative position, a required trimmed single-line Title, multiline
  plain Markdown-compatible Description, Created and Updated timestamps, and
  optional fork lineage. Use a single readable card size in v1.
- R7: Add Note is available from the Pinboard toolbar, a section affordance,
  and Command-K. Without a focused section, use the sole section directly or
  require an explicit section choice. With no sections, direct the operator to
  create one before saving a note.
- R8: Edit Title and Description in a focused native sheet with explicit
  Save/Cancel and read-only timestamps. Cards expose quiet context-menu and
  accessibility actions for Edit, Fork, and Delete. Dragging begins only from
  a clearly identifiable non-editing region.
- R9: Fork creates a new opaque ID, copies Title and Description exactly, sets
  Created and Updated to the same fork instant, records the source note ID,
  and places the independent copy in the same section at a visible clamped
  cascade offset.
- R10: Moving a note clamps it inside its section. Crossing another section's
  content boundary reparents the note and translates its position into that
  section. A note always belongs to exactly one existing section.
- R11: Layout movement and resizing change only board layout. Updated changes
  only after a saved Title or Description change. Creation and forking set
  Created and Updated to the same instant.
- R12: Delete archives a note instead of immediately destroying it. Archive
  retains the original section ID and label plus Created, Updated, and Archived
  timestamps. Restore uses the original section when it still exists;
  otherwise the operator must choose an existing destination.
- R13: Deleting an empty section requires confirmation. A nonempty section can
  be cancelled, emptied manually, or explicitly deleted with Archive Notes and
  Delete Section. No section action silently destroys notes. Permanent note
  deletion is omitted from v1.
- R14: Persist Pinboard state beneath Hyperlite's existing private XDG app-data
  root. Individual Markdown files are canonical for note identity, Title,
  Description, timestamps, lineage, and archive metadata. `board.json` is
  canonical only for schema, finite board size, sections, membership, and note
  layout.
- R15: Use opaque IDs as filenames, never titles. Bound file counts, dimensions,
  titles, descriptions, metadata, and total board data; require regular files,
  valid UTF-8 without NUL, finite numbers, known IDs, and user-only
  permissions. Serialize mutations and replace files atomically.
- R16: Malformed, oversized, unsafe, or internally inconsistent board state
  fails closed. A failed load or mutation must not overwrite recoverable source
  files; surface an explicit unavailable/error state instead of publishing a
  plausible empty board.
- R17: Pinboard is private graphical working memory only. It never becomes
  project evidence, inferred thread or attention state, PR state, project
  configuration, Notepad/Daily content, task synchronization, or agent input.
- R18: Add no timer, polling, file watcher, display link, continuous animation,
  background index, network request, GitHub mutation, or repository scan path.

Non-goals: initiatives, Kanban semantics, lifecycle lanes, WIP limits,
estimates, due dates, assignments, labels, analytics, velocity, notifications,
recurring tasks, repository links as structured entities, multiple boards,
collaboration, attachments, rich text, Markdown rendering, semantic search,
agent orchestration, or permanent deletion.

Observable acceptance:

- Workspace controls and Command-1/2 replace the complete content area beneath
  the shared header without losing Dashboard data or preferences.
- Create, edit, fork, archive, and restore preserve opaque identity, timestamp,
  lineage, original-section, and membership semantics across relaunch.
- Notes move freely and reparent only through bounded, clamped geometry.
- Sections create, rename, move, resize, and cannot silently destroy notes.
- Layout-only mutations leave note files and Updated timestamps unchanged.
- Invalid source state remains recoverable and blocks unsafe mutation.

## ACCEPTED PLAN

1. Add a dedicated Go `pinboard` package with bounded models, Markdown note
   codecs, a locked atomic store, pure geometry validation, recoverable archive,
   and one snapshot returned after each mutation.
2. Add a narrow configuration-independent `hyperlite pinboard show` and typed
   stdin mutation boundary so the native app never writes Markdown or JSON.
3. Add native Codable models, a helper client, one observable Pinboard state
   owner, and pure geometry/command models covered by executable Swift tests.
4. Refactor the native root into a shared header plus either the unchanged
   Dashboard content or full Pinboard content. Add segmented switching,
   app-focused Command-1/2, and Command-K actions.
5. Build the bounded two-axis board, movable/resizable section regions,
   fixed-size draggable cards, cross-section reparenting, explicit editors,
   safe deletion confirmation, and archive/restore presentation.
6. Validate storage invariants, command JSON, deterministic geometry, keyboard
   switching, palette actions, packaged pointer journeys, accessibility, strict
   signing, and universal architectures; then curate the spec, Constitution,
   guide, and project progress summary to delivered reality.

Rollback removes the Pinboard workspace, helper commands, and private store
without changing Dashboard or repository state. User-created private board
files remain recoverable unless the user removes them separately.

## DECISIONS

- Pinboard is a separate full-content workspace, not a Dashboard panel.
- The board uses free section-relative note placement rather than ordered card
  stacks or Kanban lanes.
- Go remains the sole filesystem authority; Swift owns transient drafts,
  gestures, sheets, and presentation.
- Note content and layout have separate canonical files so geometry changes do
  not falsify content recency.
- One finite global board and fixed-size v1 cards keep the feature bounded and
  avoid an infinite-canvas or diagramming subsystem.
- Archive is the only note deletion behavior in v1. Permanent deletion remains
  intentionally absent.
- The existing generic Refresh does not refresh Pinboard because Pinboard has
  no remote or scanned source. Each successful local mutation returns current
  state directly.

## DISCOVERIES

- Pre-implementation recon confirmed the current native root already has one
  stable shared header above a single GeometryReader containing the Dashboard's
  three equal sections, so workspace replacement can occur at that existing
  boundary without altering section sizing.
- Existing Notepad storage provides the correct XDG root, lock, permission,
  UTF-8/NUL, bounded-read, and atomic-replacement patterns, but Pinboard needs
  its own namespace and file format because layout motion must not rewrite
  note content.
- Swift sources are globbed into application builds, while executable model
  tests use an explicit source list that must include new non-view Pinboard
  models and tests.

## VALIDATION

- `go test ./internal/pinboard ./internal/cli` passed focused storage and helper
  coverage for content/layout separation, timestamp semantics, fork lineage,
  archive/restore, nonempty-section deletion safety, private regular files,
  archived-ID collision, orphan detection, malformed-source preservation, and
  strict mutation decoding.
- `make macos-test` passed Swift typechecking and executable interaction-model
  tests for snapshot coding, workspace commands, state publication, finite
  section geometry, fixed note size, clamping, and cross-section reparenting.
- `make fmt-check vet test test-race build macos-test macos-build` passed the
  complete local validation gate. The Swift compiler reported only three
  pre-existing macOS 14 `onChange` deprecation warnings in
  `HyperlitePaletteViews.swift`.
- `kit check --all` passed all ten feature artifacts. `kit check --project`
  still reports 18 pre-existing instruction-contract and unrelated legacy
  source-size findings; no Pinboard source or artifact remains in that list.
- The packaged app passed strict code-signature verification and both the
  native executable and bundled helper contained `arm64` and `x86_64` slices.
- Direct packaged-app inspection passed Command-1/2 workspace replacement,
  all five Command-K actions, section create/rename/move/resize, note
  edit/fork/cross-section drag, accessibility Edit/Fork/Delete actions,
  archive/restore, Dashboard preservation, and relaunch reconstruction. The
  journey used an isolated Pinboard data root and left the normal private board
  root absent.

## OUTCOME

Hyperlite now has one full-content Pinboard beside the unchanged Dashboard.
Its finite spatial sections and freely positioned notes remain private working
memory, persist through the bounded Go authority, preserve content timestamps
across layout motion, fork independently with lineage, and delete only into a
recoverable local archive. No network, repository, inference, task, agent, or
continuous-work behavior was added.

## REPOSITORY MEMORY

- Decision: created
- Rationale: the full-workspace boundary, private non-evidence role, split
  content/layout authority, fork and timestamp semantics, archive safety, and
  deliberately finite spatial scope are material decisions not recoverable
  from code and tests alone.
- Artifacts: `docs/specs/0010-notes-pinboard/SPEC.md`,
  `docs/CONSTITUTION.md`, `docs/USER_GUIDE.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`, and `README.md`
