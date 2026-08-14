# CONSTITUTION

## PRINCIPLES

- Hyperlite infers coordination state from the evidence a selected project
  already produces. It must not require users to create goals, link artifacts,
  assign lifecycle state, order work, or record completion in Hyperlite.
- Durable thread memory, the current working set, and human attention are
  separate projections. Attention is reserved for supported decisions,
  consequential boundaries, authoritative coordination needs, post-merge
  operational obligations, and consequential uncertainty; ordinary artifact
  motion remains progress without becoming an attention event.

## CONSTRAINTS

- Artifact completion is not goal completion. A thread may complete only when
  canonical evidence establishes delivery or reflection, anchored issues and
  pull requests are resolved, and no explicit or extracted obligation remains.
- In-flight status requires positive evidence of unresolved coordination.
  Missing canonical closure may prevent completion, but terminal-only artifacts
  and dormant intent do not remain active or retain unread attention.
- Issues and local Git state are corroborating evidence, not perpetual
  activity. Old issues, default-branch dirt, temporary automation worktrees,
  and unrelated historical specs do not establish an in-flight goal.
- An attention moment states the expected cognitive action, why it matters now,
  the consequence of inaction, and the condition that keeps it valid. Negative
  safety statements, incidental boundary keywords, ordinary metadata
  enrichment, and missing evidence alone are context, not attention;
  invalidated unread moments retire automatically. Acknowledgement survives
  unrelated evidence revisions while the underlying coordination situation is
  unchanged.
- Inferred attention remains available through CLI/JSON behind one native
  presentation boundary. While that presentation is disabled, the app omits
  thread and attention counts, rows, palette entries, and remote enrichment so
  notes and open pull requests own the interface.
- The configured-project map is a stable spatial reference, not a work-state
  or attention projection. Every configured project remains in the source
  projection; local filtering may temporarily hide a project, and clearing the
  filter restores it without changing configuration. A presented project's
  configured checkout is always identifiable, even when its subordinate lanes
  are collapsed. A subordinate registered
  worktree is visible only while its exact case-sensitive branch appears as an
  open pull-request head in current project evidence. Cached or unavailable
  pull-request data cannot retain a subordinate lane as active. No lane
  receives attention styling, and hiding a lane never deletes or prunes it.
  The Command-P palette is a navigation surface and may list every registered
  lane, including detached lanes, without establishing activity or attention.
- Noninteractive configured-project add/remove changes are explicit user
  actions written atomically and serialized across concurrent helper processes.
  Adding or removing a project changes Hyperlite's configuration only; it never
  deletes a repository, worktree, or branch.
- The configured-project pull-request index is a separate informational
  projection. Open pull requests from any author remain visible without
  establishing thread membership, liveness, lifecycle, or attention. Its
  GitHub access is read-only, bounded, cached separately from thread state, and
  refreshed only by startup or foreground staleness and explicit user action,
  never by a continuous timer. A successful refresh is authoritative for
  removing merged or closed PR branches from the visible Projects map. Cached
  rows remain available in Open PRs during a failed refresh but are not
  authoritative for active worktree visibility. Unresolved, non-outdated review
  thread counts are informational metadata in this projection; they do not
  establish inferred attention or thread lifecycle state. Caller rate-limit
  metadata rides with those same bounded GraphQL requests and is cached only as
  a complete observation; quota visibility never adds polling, changes refresh
  authority, or establishes attention. A local `Reviewed by me` marker is
  private presentation metadata bound to the exact observed pull-request head
  commit. Only current repository evidence with a nonempty head may create or
  replace a marker. A new current head invalidates that review, and only current
  repository evidence may prune it; cached or unavailable evidence cannot
  create, replace, invalidate, or prune a marker, though the operator may clear
  an existing mark. The marker never publishes GitHub state or establishes
  approval, attention, readiness, merge order, or merge authorization.
- Pinned Codex threads are a separate read-only operator projection, not
  inferred Hyperlite threads, project evidence, lifecycle state, or attention.
  A valid Desktop `pinned-thread-ids` array alone establishes membership;
  read-only SQLite metadata may enrich those opaque IDs but may not add or
  remove membership. Access is bounded and fail-closed, unavailable membership
  removes every count and row, and incomplete metadata preserves the
  authoritative count with explicit partial status. Refresh is limited to
  startup, changed source signatures after foreground activation, and explicit
  user action; Hyperlite does not poll, read transcripts, navigate, or mutate
  Codex state.
- Exact evidence owns thread membership. Semantic inference may relate
  separate threads, but it may not merge them, establish authoritative
  lifecycle state, suppress a thread, or close a goal.
- Notes and seen state are optional presentation metadata. They never create,
  order, advance, or complete project work.
- The global notepad is private operator memory, not project evidence.
  Hyperlite never interprets it as a thread, relation, obligation, lifecycle
  signal, or attention moment. Its bounded Markdown source of truth is one
  permanent pinned note plus ISO-dated daily notes; the fixed Notepad/Daily tab
  selection and derived search projection never become lifecycle authority.
  The pinned note safely adopts the prior single-document store without
  rewriting its content.
- The global Pinboard is private graphical working memory, not project
  evidence, Notepad/Daily content, task state, lifecycle state, attention, or
  agent input. It remains one finite bounded board whose stable-ID sections own
  every active note. Canonical Markdown content and timestamps are separate
  from JSON geometry and membership so layout changes cannot falsify content
  recency. Deletion is recoverable archive by default, and no section operation
  may silently destroy contained notes. Pinboard access is local, bounded,
  user-only, atomic, and fail-closed; it adds no network, repository scan,
  polling, watcher, notification, or automatic movement behavior.
- Application-controlled native interface text, including editable notepad
  content, uses JetBrainsMono Nerd Font through one shared SwiftUI/AppKit
  resolver, with the system monospaced family as the unavailable-font fallback.
  Operating-system-owned window chrome and menus retain native macOS
  typography.

### Kit-Managed Baseline Rules

<!-- BEGIN KIT-MANAGED BASELINE RULES -->
- Treat `docs/CONSTITUTION.md` as the canonical project contract.
- Keep `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` aligned with the repo-local docs tree.
- Use native agent planning for research, clarification, design, and implementation planning.
- Before implementation, inspect code and repository memory; create or adopt `SPEC.md` when material rationale exists.
- After validation, curate feature rationale, project invariants, reusable practices, and domain knowledge into their scope-appropriate canonical documents.
- Allow a justified `not required` repository-memory decision when code and tests preserve the complete durable truth.
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

- Hyperlite is not a second task tracker. It does not require manual goal,
  relationship, ordering, lifecycle, or completion bookkeeping.
- Hyperlite does not use agent lifecycle events, transcripts, continuous
  background polling, or notifications as project authority.
- Hyperlite does not select hosted models, mutate deployments, or treat
  indirect cloud observations as proof of operational completion.

## DEFINITIONS

- **Thread**: an inferred, evidence-backed projection of one project goal and
  its complete coordination lifecycle.
- **Artifact**: a source-backed issue, specification, plan, pull request,
  review, branch, worktree, or infrastructure document observed by Hyperlite.
- **Obligation**: a required outcome that must be satisfied before a thread can
  be considered complete.
- **Attention moment**: a temporary, evidence-supported relationship between a
  current situation and a useful human cognitive action, including deciding,
  guarding, reconciling, or inspecting consequential uncertainty.
- **Exact evidence**: an identifier or explicit link that can authoritatively
  establish artifact membership or lifecycle state.
- **Hypothesis**: a cited semantic relationship that may warn or explain but
  cannot merge, close, suppress, or otherwise authoritatively change a thread.
