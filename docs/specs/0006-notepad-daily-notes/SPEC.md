---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0006"
  slug: notepad-daily-notes
  dir: 0006-notepad-daily-notes
references:
  - id: issue-24
    name: Simplify Notepad around pinned and daily notes
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/24
    relation: implements
    read_policy: must
    used_for: product scope and acceptance criteria
    status: active
  - id: inferred-attention
    name: Inferred Attention
    type: specification
    target: docs/specs/0003-inferred-attention/SPEC.md
    relation: supersedes
    read_policy: must
    used_for: existing notepad persistence and private-memory boundary
    status: active
  - id: command-palettes
    name: Performant Command Palettes And Diagnostics
    type: specification
    target: docs/specs/0002-command-palettes/SPEC.md
    relation: uses
    read_policy: must
    used_for: existing Command-K architecture and keyboard behavior
    status: active
  - id: dashboard-project-management
    name: Dashboard And Project Management
    type: specification
    target: docs/specs/0005-dashboard-project-management/SPEC.md
    relation: uses
    read_policy: must
    used_for: current Notepad layout, theme, and searchable palette
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Swift state, data-adapter, and view ownership
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: validation scope and evidence
    status: active
skills: []
---

# Pinned And Daily Notepad

## PURPOSE

Replace the single scratch document with a simpler durable writing model: one
permanent pinned Markdown note and one chronological daily Markdown note at a
time. Historical notes remain ordinary local files and are reachable by date,
recent modification, or the existing Command-K search without introducing tab
or file-management concepts.

## CONTEXT

The shipped Notepad is one bounded plain-text document exposed through a Go
filesystem store and bundled CLI. `HyperliteNotepadState` keeps its draft
responsive, debounces writes for three idle seconds, and flushes on application
lifecycle boundaries. The SwiftUI surface wraps a native AppKit editor and the
dashboard allocates the whole Notes third to that one editor.

Command-K already combines a lightweight query field, pure palette-entry
models, and local keyboard capture. Its current search is synchronous literal
matching over commands only. Hyperlite has no note index, recent-note history,
or semantic search surface.

The Go helper is the established data adapter and safe writer. It already
provides bounded UTF-8 content, private permissions, atomic replacement,
filesystem locking, and configuration-independent access. These invariants
must apply independently to every pinned or daily document. Swift remains the
feature orchestrator and presentation owner; it must not become an ad hoc
filesystem writer.

## REQUIREMENTS

- R1: Store notes beneath the resolved local data root as
  `notes/pinned.md` and `notes/daily/YYYY-MM-DD.md`. Continue honoring XDG data
  placement, add a notes-directory override, and safely adopt the current
  `notepad.txt` or legacy `notepad.md` into `pinned.md` without rewriting its
  content when the pinned file does not exist.
- R2: Keep the pinned note always visible, non-closable, bounded to 256 KiB,
  and automatically saved after the existing three-second idle debounce.
- R3: Show exactly one daily note, defaulting to today in the user's current
  calendar. Load a date by its exact ISO filename and create a missing daily
  file only after the user enters content.
- R4: Provide previous-day, next-day, today, and native date-selection
  controls. Flush a dirty daily draft before changing dates so navigation
  cannot discard content.
- R5: Make the Notepad title a recent-note menu containing Today, Yesterday,
  and up to ten distinct existing daily files ordered by filesystem
  modification time. Selecting an item opens that date.
- R6: Include pinned and daily filenames, dates, and contents in Command-K.
  Literal case-insensitive substring matches rank independently and ahead of
  semantic matches. Semantic matches use Apple's on-device Natural Language
  sentence embedding and never call a network or hosted model.
- R7: Selecting a daily result opens and focuses that date's editor. Selecting
  a pinned result focuses the pinned editor. Extend the existing Command-K
  result list directly; do not add a Notes palette mode.
- R8: Load only pinned and the selected daily document into editor drafts.
  Build the derived search index asynchronously, keep indexed chunks and
  vectors rather than historical editor drafts, and upsert only a note whose
  filesystem content changes through load or save.
- R9: Normal previous, next, today, and date-picker navigation performs one
  direct daily-file read and never enumerates the daily directory. The initial
  asynchronous index build may enumerate and read historical Markdown files.
- R10: Keep Markdown files as the sole durable source of truth. The search
  index, recent ordering, selected date, focus requests, and save status are
  disposable in-memory projections.
- R11: Preserve private `0600` files, `0700` directories, atomic replacement,
  serialization, symlink rejection, NUL rejection, exact ISO-date validation,
  macOS 13 support, shared native typography, and the no-continuous-timer
  design.

Non-goals: note tabs, open-note state, close buttons, recently viewed history,
recently closed history, file browsing, file rename/delete/move controls,
Markdown preview, syntax highlighting, hosted embeddings, background polling,
or interpreting note content as project evidence.

Observable acceptance:

- The window always exposes both Pinned and one dated Daily editor; a clean
  launch selects today without creating today's file.
- Edits survive debounce, explicit navigation, and lifecycle flush at the
  exact Markdown paths.
- Date controls and the clickable Notepad recent menu open the intended daily
  document without tabs or close affordances.
- Command-K literal and semantic queries return pinned and daily results and
  activate the correct editor.
- Navigating between dates issues only direct reads for the selected date;
  historical enumeration is isolated to asynchronous index construction.

## ACCEPTED PLAN

1. Replace the single-path Go store with a notes-root store that resolves and
   validates pinned/daily paths, performs lossless legacy adoption, preserves
   bounded private atomic I/O, lists index documents only on explicit request,
   and exposes pinned/daily/index operations through the existing `notepad`
   CLI.
2. Add transport models and a process client in Swift, then refactor
   `HyperliteNotepadState` into the feature orchestrator for two active drafts,
   calendar navigation, per-document debounced saves, flush-before-navigation,
   recent metadata, and focus intent.
3. Add an actor-isolated search index. Split Markdown into bounded textual
   chunks, retain literal searchable text and on-device sentence vectors,
   rank exact matches first, and asynchronously return a capped note-result
   projection. Initial construction is an explicit CLI index read; successful
   writes update only the changed note.
4. Recompose the existing Notepad third as two controlled editor surfaces with
   compact native navigation, a clickable recent menu, clear save/error state,
   and explicit AppKit focus requests while retaining native editing, undo,
   find, scrolling, and accessibility behavior.
5. Extend Command-K's existing entry/action model with asynchronous note
   results and direct pinned/daily activation. Keep command filtering and all
   other palette modes unchanged.
6. Cover store migration/security/lazy creation/date validation/index listing,
   Swift draft/navigation/debounce/search ranking, and palette activation with
   focused tests before running the full Go and universal macOS validation
   gates and inspecting the packaged interaction.

Rollback is removal of the new note/index operations and restoration of the
single-document Swift surface. Migrated content remains recoverable as the
ordinary `notes/pinned.md` Markdown file; rollback must never silently delete
or overwrite the new daily-note files.

## DECISIONS

- The Go helper remains the sole filesystem authority. Swift requests typed
  document operations and never writes or enumerates note paths directly.
- `$XDG_DATA_HOME/hyperlite/notes` is the default notes root.
  `HYPERLITE_NOTES_PATH` overrides the root. The old
  `HYPERLITE_NOTEPAD_PATH` remains a migration source and derives a sibling
  `notes` directory when the new override is absent.
- The old document becomes the pinned note because it contains durable global
  operator context; it does not become an arbitrary dated note.
- Calendar navigation uses the current user calendar while filenames use the
  locale-independent `yyyy-MM-dd` representation of that calendar day.
- Recent notes are derived only from file modification metadata. Opening a
  note does not change its recency, and no viewed/closed history exists.
- Semantic search is a local disposable projection. Literal matches remain
  available when the system sentence embedding is unavailable, and search
  failure cannot block editing or persistence.
- Literal results suppress semantic-only results for the same query. This keeps
  a precise filename, date, or content match free of lower-confidence noise;
  semantic ranking is used when no literal result exists.
- Existing file contents win on load. In-memory drafts win only while actively
  edited and are flushed before switching away.

## DISCOVERIES

- The current helper boundary already isolates Notepad access from project
  configuration and supplies the required atomic/private storage primitives.
- The installed macOS toolchain exposes an English Natural Language sentence
  embedding with 512-dimensional vectors without adding a dependency or
  network boundary.
- The existing Command-K palette can accept typed result actions directly;
  no nested mode or new navigation architecture is required.
- The current Notepad AppKit wrapper already owns byte-bound enforcement,
  native undo/find/spellcheck, and themed accessibility behavior and can be
  reused as a controlled editor component.
- A moderate similarity floor is needed for short semantic queries because
  sentence embeddings otherwise admit superficially related notes; exact
  search remains deterministic and independent of that threshold.
- Packaged-app interaction confirmed that focusing the palette must remain an
  explicit main-run-loop action, while selecting a note result can reuse the
  existing typed palette action boundary to open and focus the target editor.
- Post-PR review exposed two fail-soft boundaries: a malformed date-named file
  must not disable indexing of every healthy note, and a transient initial
  index failure must release queued contents and permit a later rebuild.
- SwiftUI's disabled environment does not automatically make a wrapped AppKit
  text view non-editable. Navigation must project that state into `NSTextView`
  so typing cannot race a direct date load, and focus intent remains pending
  until the editor has a window and accepts first responder.
- Loading the system sentence embedding belongs inside the search-index actor
  on first use, not in the main-actor feature-state initializer.

## VALIDATION

- Focused Go storage and CLI tests pass for default/override paths, lossless
  migration, direct date reads, lazy creation, index enumeration, permissions,
  atomic concurrent writes, size/encoding/date rejection, and JSON output.
- Executable Swift tests and native type-checking pass for two-draft autosave,
  flush-before-navigation, single-read navigation, recent ordering, changed-note
  index updates, literal/semantic ranking, literal-noise suppression, and
  palette activation. Post-review recovery coverage proves a failed initial
  index can rebuild and clear its error without retaining queued note contents.
- Go index coverage proves a date-shaped but unusable daily entry is skipped
  while healthy pinned and daily documents remain searchable.
- A packaged app using an isolated notes root confirmed that Pinned and Daily
  remain visible together; Today, Yesterday, previous, next, and date selection
  open the correct note; opening a missing day does not create a file; the first
  edit creates it after the debounce; recent selection focuses Daily; and
  Command-K retrieves exact pinned content and a semantically related daily
  PostgreSQL note without unrelated results.
- `make fmt-check vet test test-race build macos-test macos-build`,
  `git diff --check`, and `kit check --all` pass. The only Swift diagnostics
  are the existing macOS 13-compatible `onChange` deprecation warnings.
- Strict deep code-signature verification passes. Both the packaged app and
  bundled Go helper contain `x86_64` and `arm64`, and the app links the system
  Natural Language framework plus Swift overlay.
- `kit check --project` reports the same eleven pre-existing main-branch
  findings in both the implementation worktree and untouched primary checkout;
  none are introduced or expanded by this feature.

## OUTCOME

Hyperlite now exposes one non-closable permanent Pinned note and exactly one
dated Daily note without tabs, open-note state, recently viewed history, or
file-management controls. The Go helper owns the Markdown filesystem boundary;
Swift keeps only the two active drafts, navigates dates with direct reads, and
maintains disposable asynchronous recency and search projections. Command-K
opens exact and on-device semantic note matches directly in the appropriate
editor.

## REPOSITORY MEMORY

Decision: created.

Rationale: storage migration, source-of-truth ownership, two-document draft
behavior, search-index authority, and the deliberate absence of tabs/history
are consequential cross-component product contracts that code and tests alone
cannot preserve.

Artifacts: `docs/specs/0006-notepad-daily-notes/SPEC.md`,
`docs/specs/0002-command-palettes/SPEC.md`,
`docs/specs/0003-inferred-attention/SPEC.md`,
`docs/specs/0005-dashboard-project-management/SPEC.md`,
`docs/CONSTITUTION.md`, `README.md`, and
`docs/PROJECT_PROGRESS_SUMMARY.md`.
