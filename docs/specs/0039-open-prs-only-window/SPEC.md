---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0039"
  slug: open-prs-only-window
  dir: 0039-open-prs-only-window
references:
  - id: issue-112
    name: "Retire agent sessions, pinboard, notes, and thread scans; keep only the Open PRs view"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/112
    relation: implements
    read_policy: must
    used_for: accepted scope
    status: active
  - id: notepad-daily-notes
    name: Notepad Daily Notes
    type: specification
    target: docs/specs/0006-notepad-daily-notes/SPEC.md
    relation: supersedes
    read_policy: optional
    used_for: retired notes surface
    status: active
  - id: agent-session-notch
    name: Agent Session Notch
    type: specification
    target: docs/specs/0011-agent-session-notch/SPEC.md
    relation: supersedes
    read_policy: optional
    used_for: retired agent-session runtime
    status: active
  - id: inferred-attention
    name: Inferred Attention
    type: specification
    target: docs/specs/0003-inferred-attention/SPEC.md
    relation: supersedes
    read_policy: optional
    used_for: retired thread scan
    status: active
skills: []
---

# Open PRs Only Window

## PURPOSE

Make Hyperlite the Open PRs list and nothing else, because that is the only
surface the operator uses.

## CONTEXT

The window still carried notes, a notes/PR split, pins and drag reordering,
an Update Default Branches action, and the CLI still carried agent sessions,
the pinboard, and the inferred-attention thread scan. Claude Code and Codex
hooks invoked `hyperlite-cli agent hook` on every session event although
nothing consumed the result.

Orchestration: multi-lane. One implementation agent removed the surfaces in
this worktree while the coordinator worked other lanes; the coordinator
reviewed and validated the result.

## REQUIREMENTS

- R1: Remove agent sessions, pinboard, notes, thread scans, pins and
  reordering, and Update Default Branches from code, CLI, docs, and tests.
- R2: Keep Open PRs (rows, review marks, hover cards, workflow strips,
  pipeline alerts, collapse, hide-idle, keyboard navigation), project
  management, Sweep Worktrees, Refresh, Command-K, theme, font size, hotkey.
- R3: Never delete operator data: note, pinboard, and thread files stay on
  disk untouched.

## DECISIONS

- The operator's agent hooks were removed from `~/.claude/settings.json` and
  `~/.codex/hooks.json` outside the repository (backups `*.bak-2026-10-04`)
  before the `agent` command was deleted, so no session hook fails.
- Projects order by newest pull request, then configuration order, now that
  custom order is gone.
- The hidden-project list shows in the full-window layout; it previously
  existed only in the removed Vertical Mode.
- Scan-only config keys still parse so existing configuration files load.

## VALIDATION

- `make fmt-check vet test-race build macos-test macos-build` passed; no
  handwritten source file exceeds 300 lines; deadcode and staticcheck U1000
  report nothing; `go list -deps ./cmd/hyperlite` is cli, command, config,
  discovery, model, prindex.

## OUTCOME

- About 25,600 lines removed. The CLI is `projects`, `pull-requests`, and
  `version`; the window is the Open PRs list.

## REPOSITORY MEMORY

- CONSTITUTION, USER_GUIDE, testing.md, README, and RUN_STATUS were rewritten
  to the reduced product; this spec records why the surfaces were retired.
