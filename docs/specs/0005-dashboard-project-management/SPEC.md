---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0005"
  slug: dashboard-project-management
  dir: 0005-dashboard-project-management
references:
  - id: issue-17
    name: Improve dashboard layout and project commands
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/17
    relation: implements
    read_policy: must
    used_for: product scope and acceptance criteria
    status: active
  - id: command-palettes
    name: Performant Command Palettes And Diagnostics
    type: specification
    target: docs/specs/0002-command-palettes/SPEC.md
    relation: supersedes
    read_policy: must
    used_for: existing palette interaction and removed prune behavior
    status: active
  - id: open-pull-requests
    name: Configured Project Pull Requests
    type: specification
    target: docs/specs/0004-open-pull-requests/SPEC.md
    relation: informs
    read_policy: must
    used_for: existing pull-request and project projections
    status: active
  - id: selene-selenized-dark
    name: Selene Selenized Dark
    type: external-reference
    target: https://github.com/santoso-wijaya/vscode-helios-selene/blob/main/themes/Selenized_Dark-color-theme.json
    relation: informs
    read_policy: evidence
    used_for: command-palette presentation tokens
    status: active
skills: []
---

# Dashboard And Project Management

## PURPOSE

Hyperlite should give Notes, Open PRs, and Projects equal, predictable space
while keeping each dense surface independently usable. Its local command
surface should be discoverable through search, expose configured project
details, and let the operator add or remove projects without manually editing
YAML or leaving the application.

## CONTEXT

The current native window gives most vertical space to the notepad and places
Open PRs and Projects in one bottom activity scroller. The notepad already owns
a native AppKit scrollbar, but the two activity projections cannot scroll
independently. Open PR freshness is rendered as a relative age, including
"Updated now", rather than an operator-auditable timestamp.

Command-K and Command-P already share one lightweight overlay and local key
capture. However, the overlay has no query field, Command-P is disabled with
the inferred-attention feature flag, and its project model is built from active
threads instead of configured projects. The scan and pull-request projections
already contain the configured project paths, pull requests, and visible
worktree lanes required for a project-first palette without background
indexing.

The Go helper already owns atomic configuration writes through
`config.AtomicWriter` and `config.ReplaceProjectPaths`, but its project selector
is TTY-only. Native add/remove actions need narrow noninteractive helper
commands so Swift remains a presentation and orchestration boundary rather
than a YAML writer. Existing stale-worktree pruning spans Swift confirmation,
state, a hidden CLI command, and a Go pruner package; the user has explicitly
removed that product capability.

Kit-managed documentation refresh is available, but its dry-run diff is
unrelated to this feature and would add six scaffold/ruleset changes. It is
intentionally deferred so GH-17 remains reviewable and reversible.

## REQUIREMENTS

- Notes, Open PRs, and Projects each receive exactly one third of the content
  workspace after fixed inter-section spacing. Each section clips to its share
  and owns a vertical scrollbar for overflow.
- Open PRs remains directly below Notes and renders its last observed GitHub
  timestamp as local date plus 24-hour `HH:mm`; missing observations remain an
  explicit availability message.
- The content header includes a ghost emoji beside `Hyperlite`; Refresh receives
  a subtle orange tint without changing its disabled or accessibility states.
- Command-R refreshes Hyperlite's thread, pull-request, and project data only
  while Hyperlite is the focused macOS application.
- Command-K opens a searchable palette of current commands. It includes
  Refresh, Settings, Add Project, and Remove Project and contains no prune
  action.
- Every palette floats at the center of the Hyperlite window with responsive
  margins at the minimum window size. Its surface, search field, selection,
  text, focus, and backdrop colors use the Selene Selenized Dark workbench
  palette.
- The native dashboard, settings, detail, and hover surfaces use the same
  Selene Selenized Dark semantic background, text, border, status, and control
  colors even when no palette is open.
- Command-P always opens the same searchable overlay in configured-project
  mode. It initially shows every configured project collapsed. Expanding a
  project shows all currently indexed open pull requests and all registered
  branch/worktree lanes for that project, including detached lanes.
- Search is case-insensitive over entry title and subtitle. Parent projects
  remain visible when a matching child PR or lane is visible, and keyboard
  selection remains valid as search or expansion changes the result set.
- Add Project is available from Settings and Command-K through a native folder
  picker. Add and Remove invoke atomic noninteractive helper operations, report
  errors in Hyperlite, and refresh projections after success.
- Remove Project is initiated from Command-K, selects from configured projects,
  and requires confirmation before the configuration write.
- Hyperlite exposes no user-triggerable worktree prune path in Swift or the Go
  helper. Detection of stale Git metadata may remain diagnostic/read-only.
- Preserve the macOS 13 deployment target, native typography, cached-first PR
  behavior, current five-minute automatic refresh floor, and no-continuous-work
  design.

Non-goals: fuzzy ranking, background file indexing, global system-wide
Command-R/K/P hooks, direct Swift YAML mutation, repository deletion, worktree
removal, branch deletion, automatic project discovery, or changing how PR data
establishes visible project lanes.

Observable acceptance:

- Resizing the window preserves three equal-height independently scrollable
  sections.
- A known observation time renders with a date and two-digit hour/minute.
- Command-R, Command-K, and Command-P act only through focused application
  commands; Command-P is available with inferred attention disabled.
- Palette typing filters results and selecting a project reveals its PR and
  lane children.
- Command-K, Command-P, and Remove Project share the same centered floating
  presentation, remain fully visible at the minimum window size, and retain
  their existing keyboard and outside-click dismissal behavior.
- Adding and removing a temporary repository changes only the project
  selection in a loadable configuration and preserves settings/inventory.
- No `prune-worktree` command or native prune action remains.

## ACCEPTED PLAN

1. Replace proportional activity sizing with a pure equal-third workspace
   calculation and compose three fixed-height section views, reusing the
   notepad's native scroller and adding separate PR/project `ScrollView`s.
2. Move freshness formatting into a pure pull-request presentation helper,
   add the focused Refresh command, and apply the small header presentation
   changes.
3. Extend the palette's pure entry model to use configured projects, PRs, and
   lanes; add case-insensitive filtering and project-preserving child matches;
   keep keyboard capture mounted only while the overlay is visible. Present
   the shared palette in a centered responsive layer using explicit Selene
   Selenized Dark tokens and no continuous visual work.
4. Add narrow `projects add` and `projects remove` helper commands that load,
   validate, atomically replace only project paths, and report idempotent
   results. Orchestrate them from `HyperliteState`, a native directory picker,
   and remove confirmation.
5. Delete the native prune flow, hidden CLI prune command, and Go pruner package
   while retaining read-only diagnostics.
6. Add focused Go and executable Swift tests, update the README and superseded
   feature specs, then run the full repository validation gate and packaged-app
   inspection before delivery.

## DECISIONS

- Use the bundled Go helper as the sole configuration writer. This preserves
  validation, canonicalization, atomic replacement, and the app's existing
  process boundary.
- Reuse the configured project/pull-request scan as palette input instead of
  introducing a new cache or filesystem index.
- Treat the palette as navigation over every registered lane, including
  detached lanes, while leaving the Projects section's current-PR filter
  unchanged. Listing a lane in the palette never establishes activity.
- Keep add/remove operations explicit and user initiated. Adding uses the
  native directory picker; removing uses the searchable project list and a
  confirmation dialog.
- Apply Selene Selenized Dark through one app-wide semantic token set. Native
  controls keep their macOS behavior, while the palette uses elevated surfaces
  and a dim backdrop to distinguish its modal layer from the themed dashboard.
- Defer unrelated Kit-managed refresh output observed during preflight.

## DISCOVERIES

- Command-P was present but suppressed whenever
  `inferredAttentionPresentation` was false, which is the shipped state.
- The notepad's AppKit editor already has a vertical scroller; only its outer
  section height needs to be fixed.
- Worktree prune capability is isolated enough to remove completely without
  changing read-only Git scan diagnostics.
- The first packaged-app check found that palette search focus remained in the
  notepad. Deferring the focus assignment by one main run-loop turn made typing
  reliably target the search field.
- Pull-request review exposed that atomic file replacement protects config file
  integrity but does not serialize a read-modify-write sequence. The
  noninteractive add/remove mutation boundary now holds the repository-standard
  process mutex and sidecar file lock from load through replacement.
- Search must generate project children before filtering, and Remove Project
  must use only the local persisted-project projection rather than the
  pull-request-backed availability fallback.
- The original top-leading root stack implicitly positioned the palette in the
  window corner. A full-window geometry layer can center the shared palette
  while a pure sizing helper preserves fixed margins and testable maximums.
- Selene's generated Selenized Dark workbench theme provides explicit widget,
  input, text, selection, and focus values. Keeping those values in a scoped
  application token type prevents ambient macOS accent colors from diluting the
  requested scheme.
- Packaged-app inspection showed that palette-only tokens restored the native
  dark dashboard as soon as the palette closed. The requested theme is an
  application appearance, so its semantic colors must be installed at every
  native scene root and at the AppKit notepad boundary.

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build` passed.
  This covered atomic project mutation commands, absence of the prune command,
  palette filtering/hierarchy, equal-third sizing, timestamp formatting,
  native type-checking, executable Swift model tests, and the universal app.
- `git diff --check` passed.
- `go test -count=5 -run '^TestConfiguredProjectMutationsSerializeAcrossProcesses$' ./internal/cli`
  passed five consecutive subprocess race reproductions.
- A separate read-only verification agent re-read all four active PR review
  threads against the integrated diff and verified D001-D004 with no blocking
  gaps before delivery.
- `kit check dashboard-project-management` passed. `kit check --project`
  continues to report the same six preflight findings for unrelated managed
  agent/testing/worktree guidance, labeling them as warnings before returning
  a blocking project-contract result. GH-17 intentionally does not mix that
  scaffold refresh into this feature.
- `codesign --verify --deep --strict build/Hyperlite.app` passed. Both the app
  executable and bundled helper contain `x86_64` and `arm64`; the bundle retains
  its identifier, executable, and icon metadata.
- A real packaged-app inspection confirmed three equal independent scroll
  regions, the ghost and orange Refresh treatment, absolute Open PR timestamp,
  persistent Selene Selenized dashboard and Settings surfaces with no palette
  open, and the centered elevated Command-K/Command-P palettes over that same
  theme. It also confirmed configured-project expansion into PRs and all
  registered lanes, the Remove Project chooser, and Settings → Add Project.
  The live inspection stopped before mutating the user's project configuration;
  isolated temporary-config tests cover both atomic write paths.

## OUTCOME

Hyperlite now presents Notes, Open PRs, and Projects as equal independently
scrollable thirds. Its focused macOS commands provide Refresh, a searchable
all-command palette, and a searchable configured-project palette. Selene
Selenized Dark now persists across the native dashboard, Settings, detail, and
hover surfaces, including when the palette is closed; both palette modes use a
centered, responsive elevated surface over that theme. Project rows expand into
open PRs and every registered lane; add/remove selection changes flow through
explicit serialized, atomic Go helper commands, with native picking and removal
confirmation. Native and helper worktree-prune actions are removed, while
read-only diagnostic evidence remains available.

## REPOSITORY MEMORY

- Created this specification for the durable cross-feature interaction,
  configuration ownership, and removed-capability rationale.
- Updated the command-palette and open-pull-request specifications with their
  superseded behavior while retaining historical decisions.
- Updated this specification with the app-wide Selene Selenized Dark
  presentation source, responsive palette-centering boundary, and closed/open
  packaged-app evidence.
- Updated `docs/CONSTITUTION.md` with the durable palette-liveness and
  serialized atomic project-selection safety boundaries.
- Updated `README.md` and `docs/PROJECT_PROGRESS_SUMMARY.md` to describe the
  current operator interface and feature state.
