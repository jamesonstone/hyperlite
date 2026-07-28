---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: 0003
  slug: inferred-attention
  dir: 0003-inferred-attention
references:
  - id: issue-7
    name: Add inferred attention threads
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/7
    relation: implements
    read_policy: must
    used_for: product scope and acceptance criteria
    status: active
---

# Inferred Attention Threads

## PURPOSE

Hyperlite reconstructs the coordination state of selected projects from the
evidence the work already produces. It groups Git, GitHub, and durable
repository-memory artifacts into goal threads, explains material dependencies
and implications, and surfaces consequential changes without requiring users
to maintain a second project-management system.

## CONTEXT

The standalone application currently treats every recent open pull request or
active worktree as an attention item. That conflates artifact presence with
human attention, hides the initiating goal and remaining operational work, and
can present stale local lanes as current even after their pull requests merge.

The intended workflow begins with research and discussion, advances through an
accepted plan and parallel implementation, absorbs automated and manual review,
then continues through merge, infrastructure, deployment, verification, and
reflection. A pull request is one artifact in that lifecycle. Hyperlite must
preserve the thread of intent and must not mistake artifact completion for goal
completion.

## REQUIREMENTS

- R1: Infer threads automatically for selected projects. Users never need to
  create goals, link artifacts, assign lifecycle states, order work, or mark
  completion in Hyperlite.
- R2: Treat GitHub issues and pull requests, Kit specs and referenced plans,
  review evidence, and material Git worktree facts as evidence with explicit
  provenance and freshness.
- R3: Determine thread membership only from exact issue, branch, pull-request,
  spec, and link relationships. Semantic inference may relate separate threads
  but may not silently merge them.
- R4: Represent each thread's goal, rationale, lifecycle phase, artifacts,
  dependencies, implications, obligations, confidence, evidence, latest
  material revision, and optional note.
- R5: Use shaping, planned, implementing, reviewing, operationalizing,
  reflecting, and complete as the lifecycle phases. A merged implementation
  pull request advances a thread but cannot complete it while explicit or
  extracted obligations remain.
- R6: Persist derived observations, remote evidence, inference results, stable
  ID aliases, seen revisions, and notes atomically in Hyperlite-owned local
  state. Preserve corrupt state before rebuilding it.
- R7: Retain cached remote evidence when GitHub is unavailable. Missing or
  failed evidence never establishes merge, closure, or completion.
- R8: Use the configured local Ollama model only for bounded, cited synthesis
  of rationale, implications, review significance, obligations, and
  cross-thread relationships. Model failure must degrade to deterministic
  evidence without failing the scan.
- R9: Create attention only for material coordination changes: decisions,
  durable direction changes, dependencies, material implications, production
  boundaries, coordination gaps, significant review challenges, and evidence
  uncertainty.
- R10: Ordinary commits, dirty-count changes, CI churn, routine review repairs,
  stale clean worktrees, and agent lifecycle events are progress evidence, not
  Jameson-attention by themselves.
- R11: On first observation, do not replay history. Emit at most one current
  moment per thread when an unresolved decision, boundary, coordination gap, or
  uncertainty exists.
- R12: The macOS app renders cached state immediately, overlays local evidence,
  refreshes remote state on foreground when stale, and performs semantic
  enrichment after deterministic results render.
- R13: The main surface separates unseen Attention from all other In Flight
  threads and omits inactive threads entirely. Completed projections remain
  available to the private state and JSON contract, but do not occupy the
  attention surface or its navigation. The menu count is the number of active
  threads with unseen moments.
- R14: Opening a thread marks moments through the displayed revision as seen
  without hiding the thread. Notes annotate existing inferred threads and never
  create, complete, or authoritatively change one.
- R15: Threads backed by positive unresolved coordination evidence are never
  hidden by an age filter. An incomplete projection without current liveness is
  dormant, not in flight, and inactive projections are not displayed.
- R16: Preserve the root JSON scan entrypoint and add bounded CLI operations for
  inference, seen revisions, and stdin-supplied notes.
- R17: Interpret lifecycle evidence according to its source workflow. A legacy
  staged feature at `reflect` is canonical reflected closure; a versioned
  living spec at `reflect` remains active until its later delivery or completion
  phase. Correcting an already-observed lifecycle classification must not replay
  a synthetic attention moment.
- R18: Derive in-flight status from positive evidence of unresolved
  coordination, not from the inability to prove canonical completion. Open
  pull requests, recently updated issue discussions, recent material changes in
  durable issue lanes, current repository-memory work, and outstanding
  post-implementation obligations can establish liveness. An old open issue,
  dirty default branch, temporary automation worktree, terminal-only pull
  request, clean published worktree, or stale isolated shaping document cannot.
  When a projection becomes inactive, retire its unread moments without
  requiring user acknowledgement.
- R19: Treat Git and GitHub evidence in tiers. An open pull request is strong
  execution evidence. An issue or worktree is corroborating evidence: an issue
  ages out without another live artifact, and local changes count only when
  recent and owned by the selected checkout or an exact durable issue lane.
  Closed issues and merged pull requests cannot be revived by generic
  requirements from an older specification.
- R20: Preserve concurrent specifications that reuse the same numeric feature
  ID in separate worktrees. Correlate each through its slug, path, and exact
  issue anchor; never let one worktree's copy overwrite an unrelated current
  goal.
- R21: Attention requires a currently supported coordination claim. Boundary
  attention requires a prospective action such as a deployment, migration,
  activation, or contract change; negative safety statements and keyword
  mentions are context only. Dependency or obligation changes require an
  authoritative dependency or an unsatisfied obligation. When stronger
  evidence invalidates an unread inferred moment, retire that moment.
- R22: Keep the main list quiet. Attention rows show the concise material
  explanation; ordinary In Flight rows show identity, project, phase, and age
  without repeating a generic `In <phase>` sentence. Full progress and evidence
  remain in thread detail.

Non-goals: user-authored task tracking, manual lifecycle management, hosted
model calls, continuous polling, notifications, agent transcript ingestion,
agent lifecycle authority, cloud-runtime inspection, deployment mutation, or
automatic project selection.

## ACCEPTED PLAN

1. Replace the reduced work-item schema with a versioned thread snapshot and
   stable evidence, relation, obligation, implication, and attention types.
2. Add a fail-soft atomic state store under
   `$XDG_STATE_HOME/hyperlite/threads.json`, defaulting to
   `~/.local/state/hyperlite/threads.json`.
3. Extend selected-project scanning with GitHub issue/review evidence, known-PR
   final-state resolution, Kit repository-memory parsing, exact correlation,
   lifecycle derivation, closure integrity, and material delta detection.
4. Add a bounded Ollama adapter that validates cited JSON, caches by evidence
   digest, and cannot alter exact membership or authoritative completion.
5. Preserve the fast local result path. Load cached remote and inference
   evidence first, then perform stale foreground refresh and semantic
   enrichment as separate bounded operations.
6. Replace the native flat list with compact Attention and In Flight sections,
   a thread detail surface, optional notes, evidence actions, and seen-revision
   persistence. Retain palettes, diagnostics, pruning, and direct artifact
   activation.
7. Validate the model with focused unit and integration fixtures, including
   distinct related R2 and Event Sink threads whose implementation pull
   requests do not satisfy their operational obligations.
8. Keep workflow-version semantics through repository-memory parsing, derive
   legacy reflected features as complete, and reconcile terminal projections
   before presenting active threads.
9. Separate liveness from completion, correlate retained terminal pull requests
   with exact local lanes regardless of age, and suppress dormant incomplete
   projections while preserving positively unresolved goals.
10. Rank evidence for liveness, restrict repository-memory scans to current
    durable lanes, preserve concurrent same-number specifications, and retain
    closed issue state for exact local anchors.
11. Require actionable boundary semantics for attention, retire moments that
    the current projection no longer supports, and remove redundant progress
    text from ordinary In Flight rows.

## DECISIONS

- The thread is an inferred projection, never a user-maintained record.
- Exact evidence owns artifact membership. Local model output is bounded
  synthesis and must remain explainable through evidence identifiers.
- Artifact completion must not be mistaken for goal completion.
- Active-thread retention follows positive unresolved coordination evidence,
  not artifact age. Lack of canonical closure can prevent completion without
  making a dormant projection currently in flight.
- Open issues and dirty worktrees are not project activity by themselves.
  Recency and corroboration determine whether they represent current
  coordination; temporary automation lanes and default-branch dirt never
  become goal threads.
- Numeric feature IDs are repository-memory identifiers, not globally unique
  lane identities. Concurrent worktrees may legitimately reuse the same next
  number until one delivery reaches the canonical branch.
- A phase label is not globally authoritative without its workflow version.
  Legacy staged `reflect` means implementation and reflection are complete,
  while V2/V3 `reflect` is an active living-spec phase.
- Reading is the only acknowledgement gesture. Hyperlite has no manual
  attention state, parking, pinning, or completion controls.
- Optional notes are durable user context, not lifecycle authority.
- Completed and dormant projections may remain in private persisted state and
  scan JSON for continuity, but the primary attention surface contains active
  coordination only.
- Selected projects remain the product boundary. Cross-repository references
  outside that set are visible only as unresolved external targets.
- GitHub/spec/Git evidence is the first complete release. Agent and runtime
  adapters are intentionally deferred.

## ACCEPTANCE CRITERIA

- AC1: Every material artifact belongs to exactly one inferred thread or is
  explicitly labeled uncorrelated.
- AC2: Active threads remain visible regardless of age, while completed and
  dormant threads are absent from the primary surface and its navigation.
- AC3: Merging a pull request with an outstanding infrastructure or deployment
  obligation leaves the thread operationalizing.
- AC4: Routine review repair and Git churn create no attention moment, while a
  design challenge, production boundary, or coordination gap does.
- AC5: Cached evidence survives a GitHub failure with visible freshness, and a
  failed or malformed local-model response preserves deterministic results.
- AC6: Opening thread detail clears unseen moments through that revision while
  retaining the thread in the in-flight view.
- AC7: Notes survive stable-ID promotion and cannot create or complete threads.
- AC8: A deterministic R2/Event Sink fixture produces separate related threads,
  cited operational obligations and implications, and incomplete operational
  closure without Hyperlite bookkeeping.
- AC9: The cached primary surface renders within two seconds in a packaged app.
- AC10: Full Go, race, Swift model, type-check, CLI build, and universal macOS
  app validation passes.
- AC11: Historical legacy reflected specs do not count as in-flight threads,
  versioned reflected specs remain active, and correcting this classification
  creates no unread attention.
- AC12: Merged-only pull requests, clean published worktrees, and stale isolated
  shaping specs create neither in-flight rows nor unread attention. They do not
  become canonically complete unless closure evidence independently supports
  that conclusion.
- AC13: A stale open issue, temporary dirty issue worktree, and dirty default
  branch create no in-flight rows, while a current open pull request and recent
  durable implementation lanes remain visible.
- AC14: Concurrent same-number specs for different issue lanes both survive
  repository-memory collection and retain their distinct goals and relations.
- AC15: Negative production-safety language and newly observed satisfied
  obligations create no attention. An actionable production boundary,
  authoritative execution dependency, or unsatisfied post-merge obligation
  does.
- AC16: Previously emitted unread guard or reconcile moments are retired when
  the current evidence no longer supports the underlying claim.

## VALIDATION MAP

- AC1-AC5: evidence, correlation, lifecycle, delta, remote-cache, and inference
  package tests.
- AC6-AC7: state mutation tests and executable Swift presentation tests.
- AC8: golden multi-repository scanner fixture and read-only live scan.
- AC9: packaged-app launch and cached-render timing.
- AC10: `make fmt-check vet test test-race build macos-test macos-build`.
- AC11: repository-memory phase contract tests, lifecycle derivation tests, and
  state reconciliation coverage for an observed active-to-terminal correction.
- AC12: positive-liveness tests for merged pull requests, exact old-PR/local-lane
  correlation, stale spec-only projections, and inactive moment retirement.
- AC13-AC14: evidence-tier, exact-lane, local-anchor retention, memory-root, and
  concurrent-spec collision tests.
- AC15-AC16: actionable-boundary, material-delta, and unsupported-moment
  retirement tests plus Swift compact-row coverage.

## DISCOVERIES

- The repository already contains richer issue, review, lane, and attention
  types inherited from Beacon, but the standalone `workscan` path discards most
  of that evidence into `WorkItem`. The feature should reuse useful evidence
  parsing while replacing Beacon's manual lane-attention semantics.
- Hyperlite's current configuration contains both discovery source roots and a
  smaller selected-project list. The accepted boundary is the selected list;
  source-root membership alone does not activate a repository.
- The existing `settings.ollama_model` field is currently unused in Hyperlite
  and can support local inference without a configuration migration.
- Active feature specs commonly exist only in an implementation worktree, not
  the selected repository's base checkout. Repository memory therefore follows
  exact non-detached worktrees and detached `GH-*` lanes while excluding clean
  detached automation checkouts.
- Kit lifecycle vocabulary in current repositories includes both canonical
  verbs and state nouns such as `implementation`, `delivery`, and
  `reflection`; all map onto the seven thread phases without changing the
  source documents.
- A first-run GitHub query must not replay closed history. Terminal PR and issue
  evidence is retained only when previously observed or exactly anchored by an
  active spec or local lane.
- The real R2 and Event Sink specs name one another's service authority without
  providing a cross-repository issue URL. Exact service-name mentions produce
  cited low-confidence `affects` hypotheses; they relate the separate threads
  but cannot change membership or closure.
- Detached daily documentation worktrees initially appeared as active goals.
  Detached state alone is not material; only dirty, conflicted, ahead, or
  otherwise unpublished Git state can create a worktree artifact.
- An artifact can disappear before canonical closure, especially for local-only
  experimental branches. The last derived active projection therefore remains
  visible as stale uncertainty while its repository stays selected; removing
  the project from selection still removes it from the product boundary.
- The configured GitHub identity's assigned-issue list is insufficient for
  closure integrity because a spec may reference an unassigned issue. Exact
  spec and `GH-*` anchors are hydrated directly within a bounded issue budget.
- Terminal PR or issue state is progress evidence, not canonical closure.
  Without a delivered canonical spec, terminal artifacts advance a thread to
  reflection rather than completing it.
- The app and CLI mutate the same state file from separate processes. Atomic
  replacement protects file integrity but not a read-modify-write transaction,
  so all writers share an advisory lock and mutation holds it from load through
  replacement.
- A native helper can emit more JSON than an operating-system pipe buffer.
  Standard output and error must be drained concurrently while the helper runs;
  reading only after termination can deadlock an otherwise healthy scan.
- Superseding a native refresh must cancel its running helper process before
  launching the replacement. Generation guards prevent stale rendering but do
  not prevent overlapping GitHub work by an obsolete helper.
- A live selected-project snapshot exposed 45 active projections: 43 were
  `reflecting`, including 31 historical Kit staged specs whose task-derived
  phase was `reflect`. Hyperlite had discarded the workflow-version distinction
  and therefore interpreted canonical legacy reflection as indefinite active
  coordination. Terminal projections also need to reach state reconciliation
  before presentation, or their prior active snapshots are retained as false
  missing-evidence uncertainty.
- After the legacy correction, the remaining 15 projections were also stale:
  13 had only merged pull requests (ten accompanied by clean worktrees), one
  was an isolated shaping spec older than the configured staleness window, and
  one was a clean published worktree whose merged pull request had aged out of
  the terminal-history window. The common defect was treating missing canonical
  completion as affirmative evidence of present liveness.
- Expanding the selected-project set exposed a second liveness failure: an old
  open weekly-maintenance issue, temporary dirty weekly-health worktrees, and a
  dirty default branch all appeared as current goals. These are weak
  information radiators; none proves present coordination without recency and a
  durable lane or stronger artifact.
- Local issue anchors were hydrated from GitHub but closed issues were then
  removed by remote-history filtering. The missing terminal fact allowed a
  temporary `GH-38` worktree to look like uncorrelated current implementation.
- LabCore issues #101 and #102 were developed concurrently from the same base
  and both legitimately allocated feature ID `0018` with different slugs and
  exact issue anchors. Repository-memory collection deduplicated only by
  feature number, causing the later scanned spec to erase the other active
  goal's rationale, relationships, and implications.
- Keyword-only boundary detection promoted fail-closed and “must not touch
  production” safety statements into guard attention. A boundary is material
  only when current evidence describes a prospective consequential action.
- Current-head review exposed two coordination-integrity edge cases: a
  non-actionable obligation digest change could mask a simultaneous goal or
  review change, and rapid replacement note saves could overlap after
  cooperative task cancellation. Material signature dimensions are evaluated
  independently, while note writes now serialize superseded tasks and guard
  cleanup by request generation.

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build` passes,
  including the Go race suite, Swift presentation tests, CLI build, and
  universal macOS application build.
- Focused tests cover exact correlation, stable ID promotion and aliases,
  lifecycle closure, material-delta classification, cached remote failure,
  atomic state persistence and corrupt-state recovery, cited Ollama contracts,
  malformed-model fallback, seen revisions, notes, cross-process mutation
  serialization, idempotent summaries, bounded exact-anchor hydration, and
  degraded inference.
- Workflow-version contract tests prove that legacy reflected specs satisfy
  their extracted obligations and become terminal while V2/V3 reflected specs
  remain active. State reconciliation coverage proves that correcting an
  observed legacy thread does not create unread attention or retain a false
  missing-evidence snapshot.
- A local-only scan against copied live state first reduced the active
  projection from 45 to 15 by removing 31 historical legacy reflected specs.
  Positive-liveness derivation then removed the remaining terminal-only and
  dormant projections, producing zero in-flight threads and zero unread
  attention while retaining six independently completed projections in scan
  state without rendering them in the primary application surface.
- Focused liveness tests cover terminal pull requests without false completion,
  exact correlation of old merged pull requests with clean local lanes,
  configured staleness for isolated shaping specs, operational obligations that
  remain active, and retirement of unread moments when a projection becomes
  dormant.
- A seven-project live scan reproduced the noisy projection at 18 total
  threads, seven in flight, and one false attention moment. Evidence-tier,
  exact-lane, and repository-memory corrections reduced the primary projection
  to three current threads: LabCore issues #101 and #102 and LabCore UI issue
  #49. The dirty default branch, temporary weekly-maintenance worktrees, old
  open maintenance issue, and unrelated historical LabCore and Kit specs no
  longer establish liveness.
- The same live scan confirms concurrent LabCore feature ID `0018` specs retain
  separate issue identities, goals, and evidence. Negative production-safety
  language and an incidental `deployed hardware` adjective produce no
  operational obligation or unread attention.
- Current-head review regressions cover simultaneous material and non-actionable
  signature deltas, boundary evidence category integrity, nested deletions,
  case-sensitive branch identity, and serialized note-save task ownership.
- A repository-wide null-delimited audit confirms every tracked handwritten
  implementation and test file is at or below 300 lines after responsibility-
  based Go and Swift splits.
- A read-only live scan of selected R2 and Event Sink repositories recovered
  separate active goal threads for issues #21 and #26, their substantial open
  pull requests, cited cross-thread hypotheses, referenced infrastructure and
  deployment obligations, implications, review state, and incomplete closure.
- The tracked local live-integration runner completed in four seconds and
  recorded immutable run `20260728T165027Z-4fc343c6`; production validation is
  not applicable to this local desktop application.
- A cached packaged-helper scan of the same repositories completed in 0.29
  seconds, within the two-second primary-content target.
- The packaged CLI and application are universal `arm64`/`x86_64` binaries and
  the application bundle passes strict code-signature verification.
- `kit check 0003-inferred-attention` passes. `kit check --project` remains
  blocked by six pre-existing V3 support-document drift findings outside this
  change; no managed instruction or worktree guidance was broadened into this
  lifecycle correction.

## OUTCOME

Hyperlite now replaces flat recent Git artifacts with automatically inferred
goal threads. It preserves active coordination state regardless of age,
distinguishes material attention from ordinary progress, retains stale remote
evidence safely, and can enrich deterministic results through the configured
local Ollama model without granting inference authority over membership or
completion. Active status now requires affirmative unresolved evidence rather
than the mere absence of canonical closure, so terminal-only and dormant
projections cannot occupy Attention or In Flight. The native experience renders
cached content first, groups unseen Attention separately from In Flight work,
omits inactive projections, and provides evidence-backed detail, seen
acknowledgement, and optional non-authoritative notes. Evidence is ranked so
that open pull requests and recent exact lanes establish current work while
stale issues, experimental local state, and unrelated worktree memory do not;
ordinary in-flight rows remain compact and reserve explanatory copy for
material attention.

## REPOSITORY MEMORY

Decision: updated.

Rationale: automatic thread inference, evidence authority, material-attention
semantics, and closure integrity are consequential product behavior that code
and tests cannot communicate completely. The Constitution now records the
cross-feature invariants and the project progress index exposes the canonical
feature state.

Artifacts: `docs/specs/0003-inferred-attention/SPEC.md`,
`docs/specs/0001-standalone-hyperlite/SPEC.md`,
`docs/CONSTITUTION.md`, and `docs/PROJECT_PROGRESS_SUMMARY.md`.
