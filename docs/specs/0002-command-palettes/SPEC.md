---
kit_metadata_version: 1
artifact: spec
workflow_version: 2
phase: deliver
clarification:
  status: ready
  confidence: 95
  unresolved_questions: 0
feature:
  id: 0002
  slug: command-palettes
  dir: 0002-command-palettes
references:
  - id: issue-5
    name: Add performant navigation, diagnostics, and ghost branding
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/5
    relation: implements
    read_policy: must
    used_for: interaction scope and acceptance criteria
    status: active
  - id: pr-6
    name: Add navigation, diagnostics, and ghost branding
    type: github-pull-request
    target: https://github.com/jamesonstone/hyperlite/pull/6
    relation: verifies
    read_policy: evidence
    used_for: review and hosted validation
    status: active
---
# Performant Command Palettes And Diagnostics

## THESIS

Hyperlite should keep the main attention list visually quiet while making every
current action quickly reachable from the keyboard. Scan diagnostics move into
a compact header control, stale worktree metadata becomes safely actionable,
concise hover cards make list items understandable without turning the viewer
into Beacon's heavier evidence surface, and a liquid-metal ghost gives the
application a precise identity at both app-icon and menu-bar scales.

## CONTEXT

The native window currently renders all scan warnings inline above the work
list. Work rows support direct activation but no keyboard discovery, selection,
or reveal state. Diagnostics are free-form strings even when Git reports a
structured prunable worktree record.

Beacon demonstrates a rich hover popover, but its delayed tasks, pinning,
focus state, animations, and large evidence views are intentionally too broad
for Hyperlite. Hyperlite must remain idle when the user is not hovering,
opening a palette, scanning, or explicitly pruning.

## CLARIFICATIONS

- The user accepted repository-scoped Git pruning because Git cannot prune one
  exact administrative record independently.
- Pruning requires confirmation and immediate re-verification that the selected
  worktree path is still prunable.
- Palette selection reveals, scrolls to, and highlights the item in the main
  list; it does not open a browser or copy a path.
- Diagnostics include errors and warnings. Only structured prunable worktree
  warnings expose a mutation button.
- Hover uses a compact custom menu rather than only the native help tooltip.
- The inferred-attention simplification in issue #7 supersedes the native
  diagnostics icon, popover, and generic Command-K Diagnostics entry described
  below. Structured diagnostics remain in CLI/JSON, while actionable verified
  stale-worktree pruning remains available through Command-K.

## REQUIREMENTS

- R1: Place a severity-colored diagnostics icon immediately to the right of
  Refresh and remove scan diagnostics from the main list flow.
- R2: Hovering the diagnostics icon shows concise read-only diagnostic details;
  clicking it pins an interactive popover with right-aligned prune buttons.
- R3: A prune action must confirm, verify the exact stale path against current
  Git porcelain output, prune all stale metadata for that repository, verify
  the target disappeared, and perform a local-only refresh.
- R4: Command-K opens a scrollable overlay containing Refresh, Settings,
  Diagnostics when present, prune actions when available, and visible work
  items.
- R5: Command-P opens a project-only overlay with all projects collapsed.
  Space expands or collapses the selected project. Arrow keys and J/K navigate
  the currently visible rows. Enter toggles a project or reveals a work item.
- R6: Every work row exposes a basic hover title and summary. Each summary is
  deterministically truncated to at most 300 characters.
- R7: Escape and clicking outside dismiss either palette.
- R8: No continuous timers, display links, animations, background indexing, or
  eager palette data construction may be introduced.
- R9: Package a 1024-pixel liquid-chrome ghost master as a complete macOS
  `.icns` set with a deterministic build step and a valid bundle icon entry.
- R10: Replace the color emoji menu-bar mark with a crisp, adaptive monochrome
  ghost silhouette and show the current attention work-item count beside it.

Non-goals: fuzzy search, persistent palette state, global system-wide Command-K
or Command-P shortcuts, Beacon-style evidence panels, automatic pruning, force
removal, branch deletion, broad repository cleanup, animated branding, or
runtime raster processing.

## ASSUMPTIONS

- Command shortcuts apply while Hyperlite is active, following normal macOS app
  command behavior.
- Palette project identity is the repository path, while the visible label uses
  the repository name.
- Work item hover content is derived entirely from the in-memory scan and never
  triggers I/O.
- There are no unresolved implementation-blocking assumptions.

## ACCEPTANCE CRITERIA

- AC1: Diagnostics no longer change the vertical position of the work list and
  remain available by hover and click.
- AC2: Non-prunable diagnostics have no action; structured prunable diagnostics
  can be confirmed, safely pruned, verified, and refreshed.
- AC3: Command-K contains every specified action and current visible work item.
- AC4: Command-P starts collapsed and implements deterministic Space,
  arrow/J/K, Enter, Escape, and outside-click behavior.
- AC5: Selecting an item in either palette scrolls to and highlights the same
  item in the main view without activating it.
- AC6: Every hover summary is at most 300 characters and no hover or palette
  mechanism performs work while idle.
- AC7: Focused Go tests, Swift interaction-model tests, type-checking, race
  tests, CLI build, and universal app build pass.
- AC8: The signed packaged app contains `Hyperlite.icns` with 16 through
  1024-pixel representations; the menu-bar label uses the ghost mark and counts
  work items rather than distinct projects.

## IMPLEMENTATION PLAN

1. Add structured prunable diagnostic fields and a tested CLI prune operation
   behind the bundled helper boundary.
2. Keep scan and mutation orchestration in `HyperliteState`; keep popovers,
   confirmation, selection, and reveal state local to the window feature.
3. Add pure presentation models for palette flattening, cursor movement, and
   hover-summary truncation so interaction logic is testable without rendering.
4. Add a small AppKit local key monitor that exists only while an overlay is
   mounted.
5. Add concise delayed hover popovers without animation, pinning, background
   polling, or retained work after dismissal.
6. Validate failure paths, exact mutation scope, keyboard state transitions,
   idle design, full builds, and the packaged helper.
7. Generate one high-resolution liquid-metal ghost master, derive the app icon
   representations during packaging, and use a code-native template silhouette
   for the menu bar so no runtime image conversion is required.

Risk: `git worktree prune --expire now` affects every stale record for the
selected repository. Mitigation: confirmation text states this scope, the
helper verifies the exact selected path immediately before pruning, and no
force/remove/branch operations are used.

Rollback is removal of the additive diagnostic fields, prune command, palette
models/views, key monitor, and hover modifier; the scan wire format remains
backward compatible because new diagnostic fields are optional.

## TASK CHECKLIST

- [x] Add structured diagnostic and safe prune helper behavior (AC2).
- [x] Add pure interaction models and focused tests (AC3-AC6).
- [x] Add diagnostics and hover popovers (AC1, AC2, AC6).
- [x] Add Command-K, Command-P, and main-list reveal (AC3-AC5).
- [x] Add the packaged application icon and counted menu-bar ghost (AC8).
- [x] Run full validation and curate repository memory (AC7).
- [x] Deliver ready PR from `GH-5`.

## VALIDATION MAP

- AC1-AC2: focused Go prune tests, Swift model tests, manual packaged-app
  diagnostic/prune interaction.
- AC3-AC6: executable Swift interaction-model tests, native type-check, manual
  packaged-app keyboard verification, and idle-process inspection.
- AC7: `make fmt-check vet test test-race build macos-test macos-build`,
  strict code-signature verification, and diff review.
- AC8: bundle-plist inspection, `.icns` round-trip inspection, signed packaged
  app launch, and real native-window rendering of the 16-pixel ghost mark.

## REFLECTION NOTES

- The safe mutation boundary belongs in the bundled Go helper. Swift requests
  an operation, while the helper canonicalizes paths, re-reads Git porcelain,
  previews the repository-scoped prune, executes it, and verifies the selected
  record disappeared.
- Palette flattening and cursor movement are pure functions. SwiftUI constructs
  only visible rows through `LazyVStack`; an AppKit key monitor exists only
  while a palette is mounted.
- The lean hover deliberately keeps only delayed open/close tasks. It has no
  pinning, animation, timer, display link, polling, focus graph, or I/O.
- The current SDK deprecates the one-parameter `onChange` overload, but the
  replacement requires macOS 14. Retaining the older overload is necessary for
  Hyperlite's macOS 13 deployment target.
- The photorealistic master and the menu-bar mark intentionally share a
  silhouette, not a raster. A code-native even-odd shape gives macOS a sharp,
  adaptive monochrome status item without loading or processing icon pixels at
  runtime.

## DOCUMENTATION UPDATES

- This specification records the durable product and safety behavior.
- `README.md` records the user-facing shortcuts and diagnostic behavior.
- `macos/Hyperlite/Assets/HyperliteIcon.prompt.md` records the generated
  artwork's reproducible design prompt and focused refinement.
- The standalone spec retains its historical rocket decision and now records
  that this feature supersedes it with the ghost/item-count identity.
- No Constitution or reusable-rule change is warranted: this is
  feature-specific interaction and safety behavior, not a new project
  invariant or cross-feature practice.

## SUPERSEDED BEHAVIOR

Issue #17 and `docs/specs/0005-dashboard-project-management/SPEC.md` supersede
the native worktree-prune action, hidden `prune-worktree` helper command, and
non-searchable palette behavior. Hyperlite now retains stale-worktree evidence
as read-only diagnostics, provides searchable Command-K and Command-P
surfaces, and uses atomic project add/remove commands instead. The original
pruning rationale remains above as historical delivery context; it is no
longer an active product or safety contract.

Issue #24 and `docs/specs/0006-notepad-daily-notes/SPEC.md` extend Command-K
with an asynchronously built, local note-search projection. This supersedes
R8's blanket prohibition on background indexing only for the bounded Notepad
index; command construction remains eager-free, no continuous timer exists,
and normal date navigation never scans historical files.

## DELIVERY DECISION

Implemented on issue #5 in branch and worktree `GH-5`. Ready pull request #6
targets `main`; delivery hard-gate recon completed with no blockers.

## EVIDENCE

- `make fmt-check vet test test-race build macos-test macos-build` passes,
  including pure Swift interaction tests and the universal packaged app.
- `git diff --check` passes. Strict code-signature verification passes, and
  both the app executable and bundled helper contain `arm64` and `x86_64`.
- A disposable Git repository verified the bundled prune command end to end:
  it detected a stale worktree record, pruned it, and verified its removal.
- The packaged app was exercised with scan diagnostics: the header icon,
  interactive popover, confirmation, Command-K navigation, Command-P
  collapse/expand behavior, and main-list reveal/highlight all behaved as
  specified. The real repository prune confirmation was cancelled to avoid
  mutating user worktrees.
- The hover length cap is covered by the Swift interaction test and the hover
  implementation is included in the native type-check and packaged build.
- Idle process samples remained between 0.0% and 0.2% CPU. Source inspection
  confirms no `Timer`, `TimelineView`, display link, or continuous animation.
- Ready pull request #6 carries the implementation from `GH-5` and closes
  issue #5 when merged.
- The packaged `Info.plist` resolves `CFBundleIconFile` to
  `Contents/Resources/Hyperlite.icns`; round-trip extraction contains every
  required 16, 32, 128, 256, 512, and 1024 representation.
- The rebuilt native app shows the adaptive ghost mark in the header. The same
  mark is used by `MenuBarExtra`, where its adjacent value is computed from the
  visible work-item array rather than the distinct-project set.
