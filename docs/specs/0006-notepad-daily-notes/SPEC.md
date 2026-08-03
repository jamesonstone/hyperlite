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
  - id: issue-30
    name: Redesign Notepad and Daily tab navigation
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/30
    relation: implements
    read_policy: must
    used_for: fixed tab presentation, calendar navigation, and observable acceptance
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
permanent Markdown Notepad and one chronological daily Markdown note at a time.
Present those two fixed document types as mutually exclusive Notepad and Daily
tabs, with Daily active by default. Historical notes remain ordinary local files
and are reachable by calendar date or the existing Command-K search without
introducing arbitrary open-note or file-management concepts.

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

The initial pinned-and-daily presentation showed both editors simultaneously,
placed previous, next, Today, and a date field on the Daily row, and used the
Notepad title as a recent-date menu. The accepted follow-up replaces that
navigation with two fixed presentation tabs and one leading calendar disclosure
so the durable and dated notes read as one coherent Notepad feature.

## REQUIREMENTS

- R1: Store notes beneath the resolved local data root as
  `notes/pinned.md` and `notes/daily/YYYY-MM-DD.md`. Continue honoring XDG data
  placement, add a notes-directory override, and safely adopt the current
  `notepad.txt` or legacy `notepad.md` into `pinned.md` without rewriting its
  content when the pinned file does not exist.
- R2: Keep the durable pinned note always available, non-closable, bounded to
  256 KiB, and automatically saved after the existing three-second idle
  debounce. Present it under the user-facing Notepad tab without a Pinned label.
- R3: Show exactly one daily note, defaulting to today in the user's current
  calendar and active by default. Load a date by its exact ISO filename and
  create a missing daily file only after the user enters content.
- R4: Present Notepad and `Daily <formatted date>` as two selectable,
  visually delineated tabs in one compact left-aligned row. Render only the
  active editor while retaining both bounded drafts in feature state.
- R5: Keep one larger disclosure chevron to the left of Notepad. It opens a
  native calendar popover; selecting a date activates Daily, updates its label,
  flushes the prior dirty daily draft, and directly loads the selected date.
  Remove the trailing Notepad chevron, Pinned label, previous/next arrows,
  Today control, right-side date field, and recent-ten-days menu.
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
- R9: Calendar selection performs one direct daily-file read and never
  enumerates the daily directory. The initial asynchronous index build may
  enumerate and read historical Markdown files.
- R10: Keep Markdown files as the sole durable source of truth. The search
  index, active tab, selected date, focus requests, and save status are
  disposable in-memory projections.
- R11: Preserve private `0600` files, `0700` directories, atomic replacement,
  serialization, symlink rejection, NUL rejection, exact ISO-date validation,
  macOS 13 support, shared native typography, and the no-continuous-timer
  design.

Non-goals: arbitrary note tabs, an open-file collection, close buttons,
recently viewed history, recently closed history, a recent-date menu, file
browsing, file rename/delete/move controls, Markdown preview, syntax
highlighting, hosted embeddings, background polling, or interpreting note
content as project evidence.

Observable acceptance:

- A clean launch selects the Daily tab for today without creating today's file.
- The fixed tab row clearly separates Notepad from `Daily <formatted date>`;
  Notepad opens the permanent durable note and Daily opens the selected date.
- Edits survive debounce, explicit navigation, and lifecycle flush at the
  exact Markdown paths.
- The sole leading disclosure opens a calendar, and choosing a date activates
  Daily and opens the intended document without recent-date or close affordances.
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
   a disposable active-tab selection, calendar navigation, per-document
   debounced saves, flush-before-navigation, and focus intent.
3. Add an actor-isolated search index. Split Markdown into bounded textual
   chunks, retain literal searchable text and on-device sentence vectors,
   rank exact matches first, and asynchronously return a capped note-result
   projection. Initial construction is an explicit CLI index read; successful
   writes update only the changed note.
4. Recompose the existing Notepad third as one controlled editor surface beneath
   a fixed Notepad/Daily tab row, a visually explicit separator, and one leading
   calendar disclosure. Retain clear save/error state and explicit AppKit focus
   requests together with native editing, undo, find, scrolling, and
   accessibility behavior.
5. Extend Command-K's existing entry/action model with asynchronous note
   results and direct pinned/daily activation. Keep command filtering and all
   other palette modes unchanged.
6. Cover store migration/security/lazy creation/date validation/index listing,
   Swift default-tab and tab-switch behavior, calendar navigation,
   draft/debounce/search ranking, and palette activation with focused tests
   before running the full Go and universal macOS validation gates and
   inspecting the packaged interaction.

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
- Notepad and Daily are two fixed presentation modes over the existing durable
  document types, not an open-note collection. Their active selection is
  disposable and does not alter filesystem authority or create history.
- Removing the recent-date menu removes its derived modification-time projection
  from Swift state and the search index. Command-K remains the bounded path for
  finding historical note content.
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
- Fixed tab selection belongs in `HyperliteNotepadState`, not view-local state,
  because Command-K note actions must activate the otherwise hidden editor
  before forwarding the existing focus request.
- A graphical native DatePicker inside a popover provides the requested month
  calendar without retaining the prior field, day-stepping, Today, or recent
  menu controls. Calendar selection can reuse the existing flush-then-direct-load
  boundary unchanged.
- A one-pixel divider plus selected pill and cyan underline keeps Notepad and
  Daily visually distinct at the minimum window width while preserving the
  compact header hierarchy.

## VALIDATION

- Focused Go storage and CLI tests pass for default/override paths, lossless
  migration, direct date reads, lazy creation, index enumeration, permissions,
  atomic concurrent writes, size/encoding/date rejection, and JSON output.
- Executable Swift tests and native type-checking pass for two-draft autosave,
  Daily-by-default selection, Notepad/Daily tab switching, full ordinal date
  labels, flush-before-calendar-navigation, single-read navigation, changed-note
  index updates, literal/semantic ranking, literal-noise suppression, and
  palette activation. Recovery coverage proves a failed initial index can
  rebuild and clear its error without retaining queued note contents.
- Go index coverage proves a date-shaped but unusable daily entry is skipped
  while healthy pinned and daily documents remain searchable.
- Packaged-app inspection confirmed Daily is selected and focused on launch;
  a vertical divider plus selected pill and cyan underline distinguish the two
  tabs; Notepad opens the durable content; the sole leading chevron opens the
  native month calendar; and selecting August 2nd closes the popover, activates
  Daily, focuses its editor, and updates the visible date. The AX tree exposes
  both tabs as selectable buttons with the active button selected.
- `make fmt-check vet test test-race build macos-test macos-build`,
  `git diff --check`, and `kit check --all` pass. The only Swift diagnostics
  are the existing macOS 13-compatible `onChange` deprecation warnings.
- Strict deep code-signature verification passes. Both the packaged app and
  bundled Go helper contain `x86_64` and `arm64`, and the app links the system
  Natural Language framework plus Swift overlay.
- `kit check --project` reports the same fourteen pre-existing main-branch
  findings in both the implementation worktree and untouched primary checkout;
  none are introduced or expanded by this feature.

## OUTCOME

Hyperlite now exposes one non-closable permanent Notepad and exactly one dated
Daily note through two fixed, visually delineated presentation tabs. Daily is
active by default, only the selected editor renders, and the sole leading
chevron opens a native calendar whose selection flushes and directly loads the
chosen day. The prior Pinned label, trailing chevron, simultaneous editors,
previous/next, Today, field date picker, and recent-ten-days menu are removed.
The Go helper remains the Markdown filesystem authority; Swift retains both
bounded drafts and a disposable asynchronous search projection. Command-K opens
exact and on-device semantic matches directly in the appropriate tab.

## REPOSITORY MEMORY

Decision: updated.

Rationale: storage migration, source-of-truth ownership, two-document draft
behavior, search-index authority, and the distinction between two fixed
presentation tabs and arbitrary open-file state are consequential
cross-component product contracts that code and tests alone cannot preserve.

Artifacts: `docs/specs/0006-notepad-daily-notes/SPEC.md`,
`docs/specs/0002-command-palettes/SPEC.md`,
`docs/specs/0005-dashboard-project-management/SPEC.md`,
`docs/CONSTITUTION.md`, `docs/USER_GUIDE.md`, and
`docs/PROJECT_PROGRESS_SUMMARY.md`.
