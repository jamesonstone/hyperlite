# CONSTITUTION

## PRINCIPLES

- Hyperlite shows open pull requests across the operator's configured
  projects. It reads the evidence those projects already produce and must not
  require users to create goals, link artifacts, assign lifecycle state, or
  record completion in Hyperlite.
- Everything Hyperlite displays is informational. It never establishes
  approval, readiness, merge order, or merge authorization.

## CONSTRAINTS

- The native window is the Open PRs list, which fills the window. It does not
  present notes, a pinboard, agent sessions, inferred threads or attention, a
  configured-project map, or a menu bar extra. The global hotkey shows the
  window and does not force a GitHub refresh. Launch does not spawn
  `projects list` until Command-P, Remove Project, Settings, or explicit
  Refresh needs the configured-project list.
- Retiring a feature never deletes the local data it wrote; Hyperlite simply
  stops reading it.
- Configured repositories remain the source list for Open PRs. Adding or
  removing a project changes Hyperlite's configuration only; it never deletes a
  repository, worktree, or branch. Command-P is a navigation lookup and may
  list configured checkouts and loaded pull requests.
- Noninteractive configured-project add/remove changes are explicit user
  actions written atomically and serialized across concurrent helper processes.
- Sweep Worktrees launches interactive `git wt sweep` in Terminal. Hyperlite
  does not pass `--auto` and does not delete worktrees itself.
- The configured-project pull-request index shows open pull requests from any
  author. Its GitHub access is read-only, bounded, cached privately, and
  refreshed only by startup, the ambient staleness check while the window is
  visible, foreground or wake staleness, and explicit user action.
  The sole automatic follow-up is the bounded workflow-activity poll: at most
  once per minute, only while a scan reports an Actions run or deployment in
  progress, only while the window is visible on screen, never longer than
  thirty minutes after a burst starts, at most sixty polls per
  quota window, and only when the cached quota observation keeps at least the
  larger of 1,000 points or thirty percent of the limit plus a projected
  twenty percent at reset. That poll never lists pull requests or reads
  workflow files, and a denied governor decision is reported, not retried.
  Cached rows remain available in Open PRs during a failed refresh.
  A refresh isolates failures per repository: pull-request detail queries
  select one repository each, only cheap probes batch repositories, and one
  slow, missing, or failing repository never fails another repository's rows.
  A configured project whose directory is gone is soft-deleted into
  `retired_projects` (restorable, with reason and time), never silently
  dropped, and configuration writes never treat a missing project directory as
  a missing configuration file.
  Only an observation younger than two minutes may present a run as currently
  running. Caller rate-limit metadata rides with those same bounded GraphQL
  requests and is cached only as a complete observation; quota visibility
  never adds polling or changes refresh authority. Quota observations may only
  deny automatic work (the activity poll, and stale refreshes below the
  automatic floor), never enable other requests or block an explicit Refresh.
- A local `Reviewed by me` marker is private presentation metadata bound to the
  exact observed pull-request head commit. Only current repository evidence
  with a nonempty head may create or replace a marker. A new current head
  invalidates that review, and only current repository evidence may prune it;
  cached or unavailable evidence cannot create, replace, invalidate, or prune a
  marker, though the operator may clear an existing mark. The marker never
  publishes GitHub state.
- Every configured project owns one Open PRs section, including projects with
  no open pull requests. Rows group under their project; there is no pinning or
  manual reordering. Projects with rows follow their most recently updated pull
  request, and projects without rows follow in configuration order. Section
  collapse, the hide-idle choice, and the quiet-ones expansion are local
  presentation state and never change GitHub state.
- Technical content, including paths, commands, arguments, messages, and
  results, uses JetBrainsMono Nerd Font through one shared SwiftUI/AppKit
  resolver, with the system monospaced family as the unavailable-font
  fallback. Native macOS chrome, controls, status labels, navigation, menus,
  and settings may use system typography so their hierarchy and accessibility
  remain consistent with the platform.
- Application theme and list type size are local operator preferences, and
  Command-K is their switch. Light themes recolor Hyperlite-painted surfaces
  and native `colorScheme`. Default remains Selenized Dark at 12 pt list type.

### Kit-Managed Baseline Rules

<!-- BEGIN KIT-MANAGED BASELINE RULES -->
- Treat `docs/CONSTITUTION.md` as the canonical project contract.
- Keep `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` aligned with the repo-local docs tree.
- Use native agent planning for research, clarification, design, and implementation planning.
- Before implementation, inspect code and repository memory; create or adopt `SPEC.md` when material rationale exists.
- After validation, curate feature rationale, project invariants, reusable practices, and domain knowledge into their scope-appropriate canonical documents.
- Allow a justified `not required` repository-memory decision when code and tests preserve the complete durable truth.
- Before a substantial terminal completion or handoff response, load `docs/references/rules/agent-completion-output.md` and report only What happened, Deviations, and Next steps; answer ordinary conversational requests naturally without that structured envelope.
- Before commit, pull request, issue, comment, or other attribution text, load `docs/references/rules/human-authorship.md`. Only the human user may be displayed as author; do not attribute coding agents, tools, or bots.
- Keep every version-control-eligible handwritten implementation/source and test file at 300 physical lines or less.
- Before delivery, audit the complete affected source/test scope; whole-project reconcile and scheduled maintenance audit the entire repository.
- Exclude documentation files, all `docs/**`, all `.kit/**`, `.kit.yaml`, ignored files, vendored dependencies, and proven generated files.
- Split oversized files by semantic responsibility while preserving stable public entry points and behavior; never use minification or arbitrary numbered chunks to claim compliance.
<!-- END KIT-MANAGED BASELINE RULES -->

## CHANGE CLASSIFICATION

<!-- all work falls into one of two tracks — classify before acting -->

### Repository-Memory Work

<!-- use when: consequential product rationale, architecture, cross-component behavior, or historical decisions must survive -->
<!-- workflow: native plan → create/adopt SPEC.md before code → implement → validate → curate repository memory -->
<!-- legacy staged documents: BRAINSTORM.md, legacy SPEC.md, PLAN.md, TASKS.md only when explicitly chosen -->

### Ad Hoc (Lightweight)

<!-- use when: bug fixes, security reviews, refactors, dependency updates, config changes, small refinements -->
<!-- workflow: understand → implement → verify -->
<!-- docs: update practical canonical docs when behavior changes -->
<!-- do not create feature SPEC.md solely for ceremony; report a justified not-required memory decision -->

### Ad Hoc with Existing Specs

<!-- if change touches code with existing spec docs: update them when rationale, behavior, requirements, or approach changes -->
<!-- leave them unchanged when code and tests communicate the complete durable truth -->

## NON-GOALS

- Hyperlite is not a task tracker or note-taking tool. It does not require
  manual goal, relationship, ordering, lifecycle, or completion bookkeeping.
- Hyperlite does not use agent lifecycle events, transcripts, continuous
  background polling, or notifications as project authority.
- Hyperlite itself does not mutate pull requests, deployments, or other
  GitHub state.

## DEFINITIONS

- **Configured project**: a local Git repository selected in Hyperlite's
  configuration whose open pull requests and workflow activity Hyperlite shows.
- **Open PRs index**: the private, read-only cache of open pull requests,
  workflow activity, and quota observations for configured projects.
