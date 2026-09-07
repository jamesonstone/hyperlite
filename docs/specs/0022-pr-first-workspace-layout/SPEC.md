---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0022"
  slug: pr-first-workspace-layout
  dir: 0022-pr-first-workspace-layout
references:
  - id: issue-75
    name: Put Open PRs on top and add Command-K vertical mode
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/75
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: lean-native-window
    name: Lean Native Window
    type: specification
    target: docs/specs/0017-lean-native-window/SPEC.md
    relation: constrains
    read_policy: must
    used_for: notes and Open PRs as the only native surfaces
    status: active
  - id: notepad-row-window-actions
    name: Notepad Row Window Actions
    type: specification
    target: docs/specs/0021-notepad-row-window-actions/SPEC.md
    relation: constrains
    read_policy: must
    used_for: quota and window actions remain on the Notepad/Daily row
    status: active
  - id: command-palettes
    name: Performant Command Palettes And Diagnostics
    type: specification
    target: docs/specs/0002-command-palettes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: Command-K-only layout toggle
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: window layout and appearance persistence
    status: active
skills: []
---

# PR-First Workspace Layout

## PURPOSE

Make Open PRs the first stacked surface, and add a persistent Command-K
vertical mode that places Open PRs on the left and notes on the right.

## CONTEXT

The window currently stacks Notepad above Open PRs. Operators scan PRs first.
A side-by-side arrangement is useful on wider windows without adding header
chrome.

Orchestration: single-lane, because window composition, appearance, and
Command-K share one layout contract.

## REQUIREMENTS

- R1: Default stacked layout shows Open PRs above Notepad/Daily.
- R2: Command-K exposes a Vertical Mode toggle. When on, Open PRs occupy the
  left pane and Notepad occupies the right pane. The choice persists locally.
- R3: Keep notepad-row window actions, Open PR behavior, and existing Command-K
  commands. Do not add Settings or header layout controls.
- R4: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Drag-resize splitters.
- Moving window actions off the Notepad row.

Observable acceptance:

- Launch shows Open PRs above notes.
- Command-K Vertical Mode puts PRs left and notes right, and relaunch keeps it.

## ACCEPTED PLAN

1. Persist `verticalMode` on `HyperliteAppearance`.
2. Compose stacked vs side-by-side panes in the window.
3. Add a Command-K toggle that marks the current vertical-mode state.

## DECISIONS

- Vertical Mode is a vim-style vertical split: a vertical divider with PRs
  left and notes right. Stacked remains the default.
- The Command-K item is a toggle, not a nested list, matching a single mode.

## DISCOVERIES

- Command-K command entries are rebuilt from current appearance, so the
  Vertical Mode checkmark updates without leaving the palette.

## VALIDATION

- `make macos-test` covers default stacked arrangement, Vertical Mode
  persistence, and the Command-K toggle marking.
- `make macos-build` produces `build/Hyperlite.app`.
- Interactive stacked vs left-right confirmation is operator follow-up after
  the packaged app is opened.

## OUTCOME

Launch stacks Open PRs above Notepad/Daily. Command-K Vertical Mode persists
a left-right split with Open PRs on the left and notes on the right.

## REPOSITORY MEMORY

- Decision: not required
- Rationale: Layout arrangement is feature-local. Operator-facing behavior is
  in the user guide.
- Artifacts: `docs/specs/0022-pr-first-workspace-layout/SPEC.md`,
  `docs/USER_GUIDE.md`, `docs/references/testing.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`
