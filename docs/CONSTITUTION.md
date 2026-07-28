# CONSTITUTION

## PRINCIPLES

- Hyperlite infers coordination state from the evidence a selected project
  already produces. It must not require users to create goals, link artifacts,
  assign lifecycle state, order work, or record completion in Hyperlite.
- Human attention is reserved for material coordination changes, consequential
  boundaries, and uncertainty. Ordinary artifact motion remains visible
  progress without becoming an attention event.

## CONSTRAINTS

- Artifact completion is not goal completion. A thread may complete only when
  canonical evidence establishes delivery or reflection, anchored issues and
  pull requests are resolved, and no explicit or extracted obligation remains.
- Exact evidence owns thread membership. Semantic inference may relate
  separate threads, but it may not merge them, establish authoritative
  lifecycle state, suppress a thread, or close a goal.
- Notes and seen state are optional presentation metadata. They never create,
  order, advance, or complete project work.

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
- **Attention moment**: a material change that requires a person to decide,
  know, guard, reconcile, or inspect uncertainty.
- **Exact evidence**: an identifier or explicit link that can authoritatively
  establish artifact membership or lifecycle state.
- **Hypothesis**: a cited semantic relationship that may warn or explain but
  cannot merge, close, suppress, or otherwise authoritatively change a thread.
