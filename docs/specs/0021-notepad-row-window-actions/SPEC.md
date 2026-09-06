---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0021"
  slug: notepad-row-window-actions
  dir: 0021-notepad-row-window-actions
references:
  - id: issue-70
    name: Collapse window actions onto the Notepad row
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/70
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: notepad-daily-notes
    name: Notepad And Daily Notes
    type: specification
    target: docs/specs/0006-notepad-daily-notes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: Notepad/Daily tab row ownership
    status: active
  - id: lean-native-window
    name: Lean Native Window
    type: specification
    target: docs/specs/0017-lean-native-window/SPEC.md
    relation: constrains
    read_policy: must
    used_for: window chrome actions for git maintenance and refresh
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: window composition of notepad chrome
    status: active
skills: []
---

# Notepad Row Window Actions

## PURPOSE

Remove the empty header band by putting GitHub quota and window actions on
the Notepad/Daily row so the editor starts immediately under one chrome line.

## CONTEXT

Removing the in-app brand left a dedicated right-aligned action row above
Notepad/Daily. That row is mostly spacer. The actions still matter; the extra
vertical band does not.

Orchestration: single-lane, because the window and notepad tab row share one
chrome composition.

## REQUIREMENTS

- R1: Put GitHub quota, Update Default Branches, Sweep Worktrees, Refresh,
  and Settings on the same row as Notepad/Daily.
- R2: Keep the same actions, help text, disable rules, and Refresh tint.
- R3: Delete the dedicated empty header row above the notepad.
- R4: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Changing Command-K, hotkeys, or action behavior.
- Restyling the quota popover.

Observable acceptance:

- The window has no empty action row above Notepad/Daily.
- Those five controls remain reachable from that row.

## ACCEPTED PLAN

Pass the existing window actions into the notepad tab header trailing slot
and delete the standalone header stack.

## DECISIONS

- Keep bordered icon buttons and the orange Refresh tint so behavior stays
  recognizable; only the empty row goes away.

## DISCOVERIES

- The notepad tab row was already a trailing HStack with Spacer and save
  status, so window actions fit there without a second chrome stack.

## VALIDATION

- `make macos-test` type-checks the window with actions on the notepad row
  and runs existing presentation-model tests.
- `make macos-build` produces `build/Hyperlite.app`.
- Interactive confirmation that the empty header band is gone is operator
  follow-up after the packaged app is opened.

## OUTCOME

GitHub quota, Update Default Branches, Sweep Worktrees, Refresh, and Settings
live on the Notepad/Daily row. The dedicated empty header row is gone.

## REPOSITORY MEMORY

- Decision: not required
- Rationale: Chrome placement is feature-local. Operator-facing behavior is
  in the user guide.
- Artifacts: `docs/specs/0021-notepad-row-window-actions/SPEC.md`,
  `docs/USER_GUIDE.md`, `docs/PROJECT_PROGRESS_SUMMARY.md`
