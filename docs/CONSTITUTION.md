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
  or attention projection. Every configured project remains present; its
  configured checkout is always visible, and a subordinate registered
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
  authority, or establishes attention.
- Exact evidence owns thread membership. Semantic inference may relate
  separate threads, but it may not merge them, establish authoritative
  lifecycle state, suppress a thread, or close a goal.
- Notes and seen state are optional presentation metadata. They never create,
  order, advance, or complete project work.
- The global notepad is private operator memory, not project evidence.
  Hyperlite never interprets it as a thread, relation, obligation, lifecycle
  signal, or attention moment. It is a bounded regular-text document; the
  default `.txt` store adopts the prior default `.md` file without rewriting
  its content.
- Application-controlled native interface text, including editable notepad
  content, uses JetBrainsMono Nerd Font through one shared SwiftUI/AppKit
  resolver, with the system monospaced family as the unavailable-font fallback.
  Operating-system-owned window chrome and menus retain native macOS
  typography.

### Kit-Managed Baseline Rules

<!-- BEGIN KIT-MANAGED BASELINE RULES -->
- Treat `docs/CONSTITUTION.md` as the canonical project contract.
- Keep `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` aligned with the repo-local docs tree.
- Treat `docs/notes/<feature>` as optional source material, not canonical truth; promote durable decisions into `SPEC.md`, `docs/CONSTITUTION.md`, or durable references.
- Use native agent planning for research, clarification, design, and implementation planning.
- Before implementation, inspect code and repository memory; create or adopt `SPEC.md` when material rationale exists.
- After validation, curate feature rationale, project invariants, reusable practices, and domain knowledge into their scope-appropriate canonical documents.
- Allow a justified `not required` repository-memory decision when code and tests preserve the complete durable truth.
- Prefer implementation/source code files around 300 lines or less when splitting improves clarity and ownership.
- Do not apply the code-file size guideline to documentation files, all `docs/**`, all `.kit/**`, or `.kit.yaml`.
- Do not split or rewrite docs, generated state, or Kit config artifacts solely because they exceed 300 lines.
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
