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
  - id: issue-11
    name: Focus native workspace on pull requests and notes
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/11
    relation: implements
    read_policy: must
    used_for: native presentation follow-up scope and acceptance criteria
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
- R13: The main surface separates active threads with unseen valid Attention
  from the rest of the current working set. Attention receives the urgent
  treatment; ordinary active threads remain available in Command-K/Command-P
  and thread detail without occupying the attention surface. Completed and
  dormant projections remain available to private state and the JSON contract
  but do not occupy active navigation. The menu count is the number of active
  threads with unseen moments.
- R14: Opening a thread marks moments through the displayed revision as seen
  and removes it from the urgent Attention list while retaining a still-current
  thread as informational activity and in working-set navigation. Notes
  annotate existing inferred threads and never create, complete, or
  authoritatively change one.
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
- R19: Treat Git and GitHub evidence in tiers. A recently updated open pull
  request is strong execution evidence, while an older open pull request
  remains current only when a supported material review decision is unresolved.
  An issue or worktree is corroborating evidence: an issue ages out without
  another live artifact, and local changes count only when recent and owned by
  the selected checkout or an exact durable issue lane. Closed issues and
  merged pull requests cannot be revived by generic requirements from an older
  specification.
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
- R22: Keep inferred attention available behind one native presentation flag,
  but disable that flag while the product focuses on open pull requests and
  notes. While disabled, do not render thread or attention counts in the window
  or menu bar, attention rows in the main surface, or thread entries in native
  palettes. CLI/JSON inference remains available.
- R23: Do not render a generic scan-diagnostics control in the native header or
  Command-K. Preserve structured diagnostics in CLI/JSON and expose only
  actionable verified stale-worktree prune commands through Command-K.
- R24: Maintain separate projections for durable thread memory, the current
  working set, and attention. An unresolved thread may be dormant, and a
  current thread may require no attention.
- R25: Every new attention moment must state the material situation, expected
  cognitive action, why the action matters now, consequence of inaction, cited
  evidence, and the condition under which the claim remains valid.
- R26: Re-evaluate attention validity on every scan. Seen and valid are
  independent: unsupported or superseded unseen moments retire automatically,
  acknowledgement survives unrelated evidence revisions while the same
  coordination situation remains supported, and a materially changed situation
  may create a new moment after an older one was seen.
- R27: Missing evidence is not attention by itself. An incomplete thread whose
  current evidence disappears becomes dormant without manufacturing an
  uncertainty moment. Stale uncertainty may surface only when a currently
  consequential decision or delivery boundary cannot be evaluated safely.
- R28: Keep the native header anchored to the top of the window. While inferred
  attention is disabled, the header contains only the product name, Refresh,
  and Settings; the Open PRs panel owns the flexible space below the notepad.
  Anchor the configured-project spatial index near the bottom as a distinct,
  low-density reference layer.
- R29: Place one always-available global notepad directly below the native
  header. Keep its draft in memory while typing, persist only the latest edit
  after three idle seconds, and flush pending content when the window or
  application yields. Store regular UTF-8 text at
  `$XDG_DATA_HOME/hyperlite/notepad.txt`, defaulting to
  `~/.local/share/hyperlite/notepad.txt`, using bounded user-only atomic writes.
  Migrate the prior default `notepad.md` file without changing its content when
  the text file does not yet exist. The notepad is optional operator memory:
  its content never enters evidence, inference, thread membership, lifecycle,
  or attention.
- R30: Project configured paths into a stable bottom map in configuration
  order. Every configured project appears even when it has no active inferred
  thread. Always show its configured checkout; expose registered non-prunable
  worktrees to native presentation, which shows a subordinate worktree only
  when its exact case-sensitive branch is present in that project's open-PR
  index. Order lanes by path without adding GitHub calls. Lane presence, branch
  age, cleanliness, and publication state do not independently establish
  activity or attention.
- R31: Use `JetBrainsMono Nerd Font` for every application-controlled text
  surface except notepad content, which uses the regular proportional system
  font to reinforce its plain-text writing role. Resolve the application font
  once through AppKit and fall back to the system monospaced font when it is
  unavailable. macOS-owned window chrome and system menus remain under
  operating-system typography.
- R32: Keep the native header on one horizontal line: while attention
  presentation is disabled it contains the product name, flexible space,
  Refresh, and Settings.

Non-goals: user-authored task tracking, manual lifecycle management, hosted
model calls, continuous polling, notifications, agent transcript ingestion,
agent lifecycle authority, cloud-runtime inspection, deployment mutation,
automatic project selection, note tabs, Markdown preview, syntax highlighting,
or model-assisted note mutation.

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
6. Replace the native flat list with a compact Attention surface, a quiet
   bottom-anchored configured-project map, thread detail, optional notes,
   evidence actions, and seen-revision persistence. Retain palettes, actionable
   pruning, and direct artifact activation while keeping generic scan
   diagnostics out of the native attention surface.
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
    the current projection no longer supports, and distinguish ordinary
    working-set activity from attention in the primary surface.
12. Make attention claims self-describing and retractable by carrying their
    expected action, consequence, and validity condition, and by retiring
    unsupported moments.
13. Treat open pull requests as strong but not perpetual working-set evidence:
    ordinary open or merged artifacts age dormant without current movement,
    while a still-supported material decision can preserve current relevance.
14. Render unseen valid attention as the primary native list, keep active
    threads available through palette and detail navigation, render configured
    projects and local paths as the plain-text reference layer, and preserve
    empty space when no attention exists.
15. Add a plain-text global notepad beneath the fixed header, backed by one
    Go-owned local text document and a three-second latest-edit debounce;
    keep Swift as the responsive draft owner and exclude the document from all
    inferred coordination paths.
16. Derive a configured-project spatial index from the local Git results
    already collected during a scan. Keep project and lane ordering stable,
    preserve configured paths when repository inspection degrades, and expose
    non-prunable worktrees for native open-PR branch projection.
17. Centralize native typography around the installed JetBrainsMono Nerd Font
    with a monospaced fallback, route SwiftUI and AppKit text through that
    boundary, and flatten the header into one baseline-aligned toolbar.
18. Temporarily disable inferred-attention presentation, migrate the notepad
    from the legacy Markdown filename to regular text, and let the open-PR
    projection decide which subordinate worktree lanes remain visible.

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
- The global notepad is a private scratch surface, not another information
  radiator. Hyperlite never interprets its contents or requires it for thread
  reconstruction.
- The notepad is regular text rather than a Markdown document. The default
  filename migrates from `notepad.md` to `notepad.txt` without rewriting
  existing content, and only editable notepad content uses proportional system
  typography.
- Completed and dormant projections may remain in private persisted state and
  scan JSON for continuity. Current working-set threads remain visible and
  navigable, but only valid unseen attention receives urgent presentation.
- Selected projects remain the product boundary. Cross-repository references
  outside that set are visible only as unresolved external targets.
- GitHub/spec/Git evidence is the first complete release. Agent and runtime
  adapters are intentionally deferred.
- Native scan diagnostics are evidence plumbing, not an attention surface.
  CLI/JSON retain the complete diagnostic record; the native UI exposes only
  actionable stale-worktree prune commands when they exist.
- Attention is a temporary relationship between a current situation and the
  user's judgment, not a durable property of a thread or artifact. The history
  may remain append-only while the active attention projection is retractable.
- Inferred attention remains implemented but its native presentation is
  temporarily disabled at one feature boundary. This preserves the evidence
  model for later re-enablement without allowing hidden attention state to
  occupy the current PR-and-notes interface.
- Artifact recency is evidence age, not importance. A consequential supported
  decision may outlive routine activity, while an ordinary untouched open pull
  request eventually leaves the current working set.
- Silence is a valid attention result. Hyperlite may show the current working
  set for orientation, but must not style, describe, or count it as attention
  when no situation currently benefits from user judgment. Empty space is part
  of that distinction; ordinary activity must not rush into the vacated
  attention area.
- The bottom project map is configuration and filesystem orientation, not
  inferred work state. Stable placement and path identity are more important
  there than recency, phase, or semantic importance.
- Project worktree visibility follows exact branches in the separate open-PR
  index rather than inferred-thread activity. A successful refresh that no
  longer reports a merged PR removes that branch's worktree from the Projects
  panel while leaving the checkout untouched.
- Typography is an application-wide presentation primitive, not a per-view
  decoration. A single resolver keeps weights and fallback behavior consistent
  across SwiftUI, the AppKit notepad editor, sheets, palettes, and settings.
- Header status is context, not a second heading. Keeping it inline with the
  product name preserves the top anchor while reducing vertical hierarchy and
  leaving the notepad immediately below the toolbar.

## ACCEPTANCE CRITERIA

- AC1: Every material artifact belongs to exactly one inferred thread or is
  explicitly labeled uncorrelated.
- AC2: Threads with positive unresolved evidence remain visible and navigable
  regardless of age. Ordinary current threads remain available through active
  navigation without being styled as Attention, while completed and dormant
  threads remain absent from the active surface.
- AC3: Merging a pull request with an outstanding infrastructure or deployment
  obligation leaves the thread operationalizing.
- AC4: Routine review repair and Git churn create no attention moment, while a
  design challenge, production boundary, or coordination gap does.
- AC5: Cached evidence survives a GitHub failure with visible freshness, and a
  failed or malformed local-model response preserves deterministic results.
- AC6: Opening thread detail clears unseen moments through that revision while
  retaining a still-current thread as informational activity and in
  working-set navigation.
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
- AC17: The native header contains no scan-diagnostics control, Command-K
  contains no generic Diagnostics entry, and actionable verified
  stale-worktree prune commands remain available.
- AC18: An ordinary open pull request without recent movement becomes dormant;
  a currently supported unresolved design decision remains active and
  attention-worthy.
- AC19: Unsupported attention retires without acknowledgement, ordinary goal
  or title enrichment creates no attention, and disappearing evidence demotes
  an incomplete thread without creating an uncertainty alert.
- AC20: Every emitted moment includes a non-empty expected action, consequence,
  and validity statement in addition to its explanation and evidence.
- AC21: With inferred-attention presentation disabled, the native header shows
  no thread or attention counts, the main surface and palettes render no
  attention threads, and CLI/JSON inference behavior remains intact.
- AC22: A borderless global notepad appears immediately below the header,
  remains responsive without per-keystroke processes or writes, saves only the
  latest edit after three idle seconds, flushes on application or window
  deactivation, survives relaunch as regular text, safely adopts the prior
  default Markdown file, rejects content above 256 KiB, and remains absent from
  thread and attention projections.
- AC23: The project map contains every configured project in stable
  configuration order, always includes its configured checkout, adds real
  registered worktree paths only when their exact branch has an open PR in
  that project, excludes prunable metadata, and removes a lane after a
  successful refresh observes its PR merged. Building it performs no
  additional GitHub commands.
- AC24: Every application-controlled text view resolves to JetBrainsMono Nerd
  Font when installed and to the system monospaced family otherwise; notepad
  content alone uses the regular proportional system font. The main header
  renders the product name, Refresh, and Settings in one horizontal row while
  attention presentation is disabled.

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
- AC17: executable Swift palette regression, native type-check, packaged app
  header inspection, and Command-K accessibility inspection.
- AC18-AC20: liveness, moment-contract, metadata-enrichment, missing-evidence,
  and high-consequence uncertainty tests.
- AC21: executable Swift projection and palette-navigation regressions plus
  packaged native hierarchy inspection.
- AC22: Go path, permission, bound, atomic-write, and CLI tests; executable
  Swift load/debounce/flush tests; packaged editor interaction and relaunch
  inspection.
- AC23: deterministic project-index projection tests, schema decoding and path
  presentation tests, command-count regression, and packaged native visual
  inspection.
- AC24: executable typography resolver tests, native type-check, packaged
  AppKit font inspection, and minimum-width header hierarchy inspection.

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
  experimental branches. The initial policy retained that projection as stale
  uncertainty, but live use proved absence alone is not a present cognitive
  demand. Hyperlite now preserves the private record for continuity while
  demoting the thread and retracting its unread attention.
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
- Historical prose can contain present-tense action words such as “changes”
  without describing a pending boundary. Classification is clause-aware:
  completed clauses remain quiet, historical clauses require explicit current
  intent, and a separate current clause may still establish a boundary.
- The generic Command-K Diagnostics entry only forwarded into the header
  diagnostics popover. Removing the header control therefore requires removing
  that command and its presentation state together; verified prune commands
  remain independent and actionable.
- Current-head review exposed two coordination-integrity edge cases: a
  non-actionable obligation digest change could mask a simultaneous goal or
  review change, and rapid replacement note saves could overlap after
  cooperative task cancellation. Material signature dimensions are evaluated
  independently, while note writes now serialize superseded tasks and guard
  cleanup by request generation.
- Expanding from seven to sixteen selected projects exposed a distinction
  between evidence enrichment and a change in direction. A local lane first
  appeared as `GH-35`, then gained its issue title and description after remote
  hydration; comparing those derived goal strings emitted a false “direction
  changed” alert. Goal or title metadata changes are now quiet unless current
  evidence independently establishes a decision, consequential boundary,
  authoritative coordination need, or post-merge operational obligation.
- Material revisions are broader than attention situations. Local and remote
  scans can change thread rationale, relations, freshness, or inference state
  while the same operational obligation remains unresolved. Re-emitting that
  obligation after it was seen turns refresh into interruption, so
  reconciliation fingerprints the supported coordination situation separately
  from the complete thread revision.
- Uncertainty acknowledgement is scoped to the exact stale evidence, not the
  generic user-facing uncertainty summary. Current-evidence enrichment stays
  quiet, while a different stale consequential artifact creates a distinct
  situation that can require renewed verification.
- Beacon's useful Notes boundary is smaller than its complete notes feature:
  one XDG Markdown document, a 256 KiB bound, atomic user-only writes, an
  in-memory editor draft, and a three-second latest-edit debounce. Hyperlite
  needs those persistence and responsiveness properties, but not Beacon's
  tabs, styled Markdown, agent protocol, assistant, or note-derived context.
- A live project-index prototype that included every registered worktree
  immediately reproduced the stale-evidence problem: Kit and Docs retained
  dozens of historical and detached automation checkouts. The configured
  checkout is the stable spatial anchor; subordinate paths remain useful only
  when an active thread cites that exact worktree. Reusing the already-collected
  local scan preserves this distinction without another Git or GitHub call.

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
- A live scan of the expanded sixteen-project configuration reconstructed 21
  retained threads and 11 current working-set threads. The first remote
  hydration emitted four unread moments; three were false goal-change notices
  caused only by lane titles gaining issue metadata. Fail-closed delta handling
  retired those notices, leaving one supported Attention item: R2's merged
  implementation with an unsatisfied operational obligation.
- The same live scan confirms concurrent LabCore feature ID `0018` specs retain
  separate issue identities, goals, and evidence. Negative production-safety
  language and an incidental `deployed hardware` adjective produce no
  operational obligation or unread attention.
- Current-head review regressions cover simultaneous material and non-actionable
  signature deltas, boundary evidence category integrity, nested deletions,
  case-sensitive branch identity, historical versus prospective boundary
  language, and serialized note-save task ownership.
- A repository-wide null-delimited audit confirms every tracked handwritten
  implementation and test file is at or below 300 lines after responsibility-
  based Go and Swift splits.
- The new attention contract and presentation retain that boundary: the largest
  touched implementation files are `internal/threadstate/reconcile.go` at 297
  lines, the Swift interaction test at 294, and
  `internal/threadstate/attention.go` at 289.
- Notepad store and CLI tests prove XDG path resolution, configuration-
  independent access, verbatim round trips, legacy `notepad.md` adoption into
  the default `notepad.txt` path, `0600` file and `0700` directory permissions,
  atomic replacement, concurrent-writer serialization, and rejection of
  symlinks, NUL bytes, and content above 256 KiB.
- Executable Swift tests prove that the editor loads persisted content, a
  three-second debounce retains only the newest edit, lifecycle flush bypasses
  the debounce, successful writes clear dirty state, and oversized drafts are
  rejected without replacing the in-memory document.
- Repeated local and remote scans against the expanded configuration preserved
  the R2 attention-history count exactly after acknowledgement, proving that
  deterministic projection changes do not re-emit the same operational
  obligation.
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
- Packaged-app accessibility inspection confirms that the header contains only
  Refresh and Settings controls, Command-K contains no Diagnostics entry, and
  current prunable worktree warnings still produce verified prune commands.
- Packaged-app visual and accessibility inspection confirms that the header
  remains top-anchored and contains only the product name, Refresh, and
  Settings while the native attention feature flag is disabled. No thread or
  attention counts, rows, or palette entries occupy the interface.
- Packaged-app inspection confirms that the accessible borderless notepad sits
  immediately below the header and renders editable content in the
  proportional system font without Markdown presentation.
- Go project-index tests prove that configured order and missing configured
  paths survive degraded discovery, primary checkouts remain present,
  prunable lanes stay absent, and registered subordinate worktrees are exposed
  without another GitHub scan. Swift projection tests prove that only exact
  case-sensitive open-PR head branches render those subordinate lanes.
- An isolated-cache live native inspection of all sixteen configured projects
  rendered eighteen open PRs and only their matching subordinate worktree
  branches while preserving every configured checkout. A successful empty PR
  projection is covered to remove merged or closed lanes without local
  deletion.
- Packaged-app accessibility and visual inspection confirms a bottom-anchored
  two-column plain-text project map with `Projects 16`, full path accessibility
  labels, home-relative visible paths, no cards, and no alert, phase, age, goal,
  or attention styling. Open PRs owns the flexible region between the notepad
  and Projects.
- `kit check 0003-inferred-attention` passes. `kit check --project` remains
  blocked by six pre-existing V3 support-document drift findings outside this
  change; no managed instruction or worktree guidance was broadened into this
  lifecycle correction.

## OUTCOME

Hyperlite now replaces flat recent Git artifacts with automatically inferred
goal threads. It distinguishes durable thread memory, the current working set,
and the temporary situations that benefit from human attention. Active status
requires affirmative unresolved evidence rather than the mere absence of
canonical closure, while attention additionally requires a supported decision,
consequential boundary, authoritative coordination need, or post-merge
operational obligation. Missing evidence, ordinary metadata enrichment, and
routine artifact motion remain quiet.

The native presentation of inferred attention is temporarily disabled behind
one feature boundary while the product focuses on notes and open pull
requests. The evidence model, CLI/JSON inference, reconciliation, and seen
history remain intact, but the native window, menu bar, and palettes omit
thread and attention counts and entries and skip remote attention enrichment.
The fixed header contains only the product name, Refresh, and Settings.
Diagnostic data stays in CLI/JSON and only actionable verified pruning enters
Command-K.

The same surface now includes one quiet global notepad immediately below the
header. Its native editor keeps keystrokes in memory, performs no styling or
project interpretation, and sends only the latest idle draft to a bounded
Go-owned regular-text store. The default `notepad.txt` path safely adopts the
prior default Markdown file without changing its contents. Autosave and
lifecycle flush preserve the document across relaunches without allowing its
content to create or alter a thread, goal, obligation, or attention moment.

Application interface text continues to resolve through one JetBrainsMono Nerd
Font boundary with a system monospaced fallback, while editable notepad content
uses the regular proportional system font. The bottom Projects map always
retains configured checkouts and now renders a subordinate registered worktree
only while its exact branch is present in that project's Open PRs projection.
A successful refresh after merge hides the lane without deleting or pruning
local data.

## REPOSITORY MEMORY

Decision: updated.

Rationale: automatic thread inference, evidence authority, material-attention
semantics, closure integrity, and the boundary between private scratch text and
project evidence are consequential product behavior that code and tests cannot
communicate completely. The shared application typography contract is also a
project-wide visual invariant. The Constitution records those cross-feature
boundaries and the project progress index exposes the canonical feature state.

Artifacts: `docs/specs/0003-inferred-attention/SPEC.md`,
`docs/specs/0001-standalone-hyperlite/SPEC.md`,
`docs/CONSTITUTION.md`, and `docs/PROJECT_PROGRESS_SUMMARY.md`.
