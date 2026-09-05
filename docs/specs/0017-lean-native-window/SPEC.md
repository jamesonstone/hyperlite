---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0017"
  slug: lean-native-window
  dir: 0017-lean-native-window
references:
  - id: issue-64
    name: Slim Hyperlite to notes, Open PRs, and local git maintenance
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/64
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
    used_for: retained notes surface
    status: active
  - id: open-pull-requests
    name: Configured Project Pull Requests
    type: specification
    target: docs/specs/0004-open-pull-requests/SPEC.md
    relation: constrains
    read_policy: must
    used_for: retained Open PRs projection
    status: active
  - id: deletion-safety
    name: Deletion Safety
    type: ruleset
    target: docs/references/rules/deletion-safety.md
    relation: constrains
    read_policy: must
    used_for: sweep launches git-wt; Hyperlite does not hard-delete worktrees
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: window composition and git-maintenance actions
    status: active
  - id: backend-architecture
    name: Backend Service Architecture
    type: ruleset
    target: docs/references/rules/backend-service-architecture.md
    relation: constrains
    read_policy: must
    used_for: CLI command to git-maintenance service boundary
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Go fast-forward tests and native presentation tests
    status: active
skills: []
---
# Lean Native Window

## PURPOSE

Make Hyperlite the smallest, fastest native window for notes and Open PRs,
with two explicit local git-maintenance actions: fast-forward every configured
default branch, and kick off interactive `git wt sweep`. Remove unused
surfaces so launch does not start thread scans, pinboard, agent sessions, or
a notch panel.

## CONTEXT

The operator uses the window for Notepad/Daily and Open PRs. The Projects
column, Pinboard, Agent Tasks, Agent Island, pinned Codex header, and menu
bar extra are unused and cost CPU, memory, and layout complexity. The
equal-thirds GeometryReader dashboard previously contributed to layout
instability.

Configured projects still exist as the source list for Open PRs and git
maintenance. They do not need a dashboard map.

`git wt sweep` already classifies and confirms worktree removal. Hyperlite
must start that interactive tool rather than auto-deleting worktrees.

## REQUIREMENTS

- R1: The native app is one window with notes and Open PRs. No workspace
  switcher, Pinboard, Agent Tasks, Agent Island, pinned Codex, or menu bar
  extra.
- R2: Launch and Refresh do not scan inferred threads, start the agent
  helper, load pinboard, or observe Codex pins. Refresh updates Open PRs
  and the current daily-note date.
- R3: Settings still add and remove configured projects. Command-K keeps
  Refresh, Force Cache Refresh, Copy Open PR Merge Prompt, notes search,
  Settings, Add Project, Remove Project, Update Default Branches, and
  Sweep Worktrees.
- R4: Update Default Branches fast-forwards each configured repository's
  default branch when Git allows a clean fast-forward. Skip dirty trees,
  non-fast-forward histories, and checked-out refs Git refuses to update.
  Never reset, stash, force, or delete branches.
- R5: Sweep Worktrees opens interactive `git wt sweep` in Terminal. It
  does not pass `--auto` and does not delete worktrees itself.
- R6: Dashboard notes and Open PRs share the window without a
  GeometryReader equal-thirds split.
- R7: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Reimplementing `git wt sweep`.
- Hyperlite-owned worktree hard delete.
- Removing the Go CLI scan/infer/agent/pinboard commands in this change.
- Changing Open PRs GitHub read-only refresh authority.

Observable acceptance:

- Launch shows notes and Open PRs only.
- Command-K has no Pinboard, Agent Tasks, or Agent Island actions.
- Update Default Branches reports per-repository updated, skipped, or
  failed outcomes without discarding unique local work.
- Sweep opens Terminal running `git wt sweep`.

## ACCEPTED PLAN

1. Add a Go git-maintenance service and `hyperlite projects list --json` plus
   `hyperlite projects update-defaults --json`.
2. Stop native launch-time thread, pinboard, agent, island, Codex, and menu
   bar work. Always show the main window.
3. Replace the three-pane dashboard with notes above Open PRs. Add header
   and Command-K actions for update-defaults and sweep.
4. Delete unused native sources and tests. Keep CLI packages that this
   change does not invoke.
5. Update the user guide, README, constitution native-window constraints,
   and testing reference.

Topology: `single-lane, because tightly coupled`. The window cut, launch
lifecycle, and git-maintenance CLI share one product contract.

## DECISIONS

- Delete unused native surfaces instead of hiding them behind flags.
- Leave Go CLI scan/infer/agent/pinboard commands in place so this change
  stays a native-runtime cut plus two git actions.
- Fast-forward only. Dirty or divergent default branches are skipped with
  an explicit reason.
- Sweep is a Terminal launch of the real `git wt sweep` so confirmation
  stays in that tool.

## DISCOVERIES

- Native launch still ran a local thread scan to populate the Projects map
  even while inferred-attention presentation was off.
- `git wt sweep --auto` would be a Hyperlite-triggered hard delete; the
  interactive command already owns confirmation.
- `~/.local/bin` is where `git-wt` lives and was missing from the app PATH.

## VALIDATION

- `go test ./internal/gitmaint ./internal/cli` passed, including dirty-skip,
  side-branch update, checked-out-ref skip, fetch failure, project list JSON,
  and update-defaults JSON.
- `make fmt-check vet test macos-test` passed. Native type-check and
  executable model tests cover Command-K without unused workspace actions,
  helper PATH including `~/.local/bin`, and default-branch update summaries.
- `make macos-build` produced an ad-hoc signed universal `Hyperlite.app`.

## OUTCOME

The native app is one window with notes above Open PRs. Launch no longer
starts thread scans, pinboard, agent sessions, Agent Island, pinned Codex, or
a menu bar extra. Update Default Branches fast-forwards configured default
branches when Git allows; Sweep Worktrees opens interactive `git wt sweep`.
Go CLI scan/infer/agent/pinboard commands remain for this change.

## REPOSITORY MEMORY

- Decision: created
- Rationale: withdrawing unused native surfaces and adding bounded local
  git maintenance is product intent that tests cannot fully preserve.
- Artifacts: `docs/specs/0017-lean-native-window/SPEC.md`,
  `docs/CONSTITUTION.md`, `docs/USER_GUIDE.md`, `docs/references/testing.md`
