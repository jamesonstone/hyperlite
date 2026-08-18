---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0012"
  slug: agent-session-runtime-reliability
  dir: 0012-agent-session-runtime-reliability
references:
  - id: issue-51
    name: Improve agent-session runtime reliability
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/51
    relation: implements
    read_policy: must
    used_for: accepted scope, resource budgets, and observable acceptance
    status: active
  - id: agent-session-notch
    name: Agent Sessions And Notch Companion
    type: specification
    target: docs/specs/0011-agent-session-notch/SPEC.md
    relation: constrains
    read_policy: must
    used_for: exact identity, privacy, provider, action, and presentation boundaries
    status: active
  - id: ping-island-0271
    name: Ping Island v0.27.1
    type: external-reference
    target: https://github.com/erha19/ping-island/blob/main/releases/notes/0.27.1.md
    relation: informs
    read_policy: evidence
    used_for: clean-room replacement and truncation recovery priorities
    status: active
  - id: ping-island-0240
    name: Ping Island v0.24.0
    type: external-reference
    target: https://github.com/erha19/ping-island/blob/main/releases/notes/0.24.0.md
    relation: informs
    read_policy: evidence
    used_for: clean-room auxiliary-session filtering priorities
    status: active
  - id: backend-architecture
    name: Backend Service Architecture
    type: ruleset
    target: docs/references/rules/backend-service-architecture.md
    relation: constrains
    read_policy: must
    used_for: service ownership, adapters, bounded state, and process lifecycle
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Swift projection, orchestration, and native settings presentation
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: deterministic, live, packaged, physical, and resource evidence
    status: active
skills: []
---

# Agent-Session Runtime Reliability

## PURPOSE

Make Hyperlite reliably discover and track current local coding-agent sessions
for indefinite use without meaningful idle CPU, memory, battery, file-I/O,
watcher, descriptor, task, or child-process growth. The runtime should recover
from hookless sessions and rollout-file lifecycle changes while preserving the
exact identity, privacy, permission, and macOS presentation contracts delivered
by feature 0011.

## CONTEXT

Feature 0011 established an event-driven Go session authority, private hook
socket, documented Codex app-server stdio adapter, bounded rollout fallback,
ephemeral redacted state, exact capability-gated actions, and shared Swift
Sessions/notch projections. Issue 49 then made external idle presentation fully
transparent and allowed exact app-server rollout hints to recover cross-process
Codex sessions.

The remaining reliability gap is lifecycle depth. A fixed rollout-watcher map,
bounded tail reparsing, and launch-lived app-server can miss newly created
hookless sessions, spend avoidable resources, or fail to recover cleanly across
replacement, truncation, midnight, and long-running operation. This feature
extends the same authority rather than creating a parallel engine.

The Ping Island release notes are priority evidence only. Hyperlite remains a
clean-room implementation, keeps stdio instead of experimental fixed-port
WebSocket transport, and copies no upstream source, assets, or branding.

## REQUIREMENTS

- R1: Replace fixed rollout observation with a lifecycle-managed registry
  capped at 32 watchers. Release capacity immediately when a session ends or
  expires, an integration disables, a file disappears, or exact identity
  changes. Admit by attention, active processing, fresh idle, then recent
  completion; evict only the oldest non-attention watcher.
- R2: Watch only the current local Codex date directory for new rollout files,
  rebind at the next local-day boundary, and perform bounded discovery only on
  startup, foreground activation, explicit refresh, or directory events.
- R3: Parse rollout changes through an incremental cursor containing file
  identity, byte offset, partial-line state, oversized-line discard state, and
  normalized projection. Read 64 KiB chunks and process at most 512 KiB or 128
  records per event-loop turn. Cap initial discovery at 32 MiB total and retain
  no raw record after normalization.
- R4: Detect file replacement, rename, truncation, and inode change. Reopen and
  rebuild from a bounded tail without losing the exact seed identity. Never
  enrich or store a rollout whose parsed identity differs from its seed.
- R5: Suppress already-expired discoveries before projection and do not advance
  the snapshot generation when the observable projection is unchanged.
- R6: Own at most one Codex app-server child through one start, refresh, and
  stop controller. Start for launch discovery, stale foreground/manual
  discovery, integration self-test, or exact live response need; reuse it and
  terminate it within 120 seconds after discovery and live-response work quiet.
- R7: Keep documented app-server stdio initialization, bounded pagination,
  supported notifications, and notLoaded fallback. Hooks and rollout evidence
  remain authoritative after the child exits.
- R8: Add agent_session_control.v1 operations for foreground_refresh,
  manual_refresh, and integration_self_test. Swift sends foreground refresh
  only when discovery freshness requires it.
- R9: Add memory-only agent_integration_health.v1 records with only
  provider/profile, transport, connection state, last event/acknowledgement,
  watcher utilization, filtered/rejected counts, self-test outcome, and bounded
  error code. Exclude content, arguments, paths, raw envelopes, and secrets.
- R10: Verify Integration sends one unique synthetic metadata-only event
  through the actual bridge, socket, store, and UI acknowledgement path, removes
  its synthetic row immediately, and never invokes a provider or approves an
  action.
- R11: Conservatively suppress auxiliary maintenance, title-generation, and
  blank pre-prompt Codex rows only from explicit metadata or multiple
  corroborating empty-placeholder signals. Never filter from cwd or time alone.
  Delay blank visibility for a cancellable two-second grace and publish
  immediately on real prompt, exact rollout identity, intervention, or tool.
- R12: When a provider supplies an exact PID and process-start token, use
  event-driven exit observation. Never scan process names. Sessions without
  exact process proof retain ordinary event and expiry semantics.
- R13: Replace one pending action with a queue capped at eight exact
  provider/session/request/revision identities. Resolve and retract each
  independently. Notify-only and rollout-derived requests remain non-actionable.
- R14: Add agent_session_snapshot.v2 and agent_session_action.v2. Swift accepts
  v1 and v2 for one compatibility release, maps a v1 action to a one-element
  queue, and the final helper emits v2. Hook and routing persistence schemas do
  not change.
- R15: Sessions and notch detail show the current action and pending count.
  Collapsed presentation remains metadata-only.
- R16: Retain a memory-only ring of 256 content-free phase transitions with
  timestamp, provider, opaque session ID, source, old/new phase, and bounded
  reason code. Clear it on exit.
- R17: Coalesce ordinary session snapshots to at most four per second during
  bursts while emitting approval, input, and error transitions immediately.
  Use no continuous UI timeline, animation loop, transcript scan, periodic
  project scan, or background self-test.
- R18: When settled, retain only the next expiry, app-server quiet, and
  day-boundary deadlines. Bound state at 32 watchers, 100 sessions, eight
  actions per session, six display messages, 256 transitions, and existing text
  limits.
- R19: Keep session content memory-only and routing metadata-only. Never persist
  health, transitions, PIDs, action queues, or self-test payloads.
- R20: Preserve macOS 13 universal support, exact owned-process cleanup, first-
  run consent, provider-native permission authority, fully transparent
  external-display idle presentation, and HYPERLITE_AGENT_SESSIONS_PREVIEW=0
  rollback.
- R21: Add Settings health details and per-provider Verify Integration using
  native, keyboard-accessible, VoiceOver-meaningful macOS controls.
- R22: Treat resource operation as release behavior: combined app/helper idle
  CPU averages at most 1% over 30 minutes after warmup; helper RSS is at most
  75 MiB with 32 watchers and 100 synthetic sessions; app-server absence occurs
  within 120 seconds of quiet; file reads require an event/control/refresh; and
  an eight-hour idle soak shows no upward watcher, descriptor, task, or RSS
  trend with less than 10% RSS growth after warmup.
- R23: Attention projection latency remains under 250 ms and ordinary updates
  settle within one second. Sleep/wake, display migration, midnight rebinding,
  and relaunch leave no duplicate watcher or child.
- R24: Keep usage/quota analytics, SSH bridging, transcript backfill,
  telemetry, mascots, and detached companions outside this feature.

## ACCEPTED PLAN

1. Introduce bounded rollout cursor, watcher-registry, date-directory, and
   discovery components behind the existing service authority, with exact
   identity checks and explicit lifecycle release.
2. Refactor Codex app-server ownership into one adaptive controller and add the
   typed control channel used by launch, stale foreground refresh, manual
   refresh, and integration self-test.
3. Extend the in-memory domain with health, conservative blank/auxiliary
   filtering, exact process-exit evidence, queued interventions, transition
   history, and semantic snapshot scheduling.
4. Emit v2 snapshot/action records while keeping one-release v1 Swift decoding;
   preserve hook and routing schemas and all content/redaction limits.
5. Extend native session state, Settings, and notch/session detail with
   freshness-aware control, metadata-only health, Verify Integration, and
   pending-action count.
6. Add deterministic unit, contract, integration, compatibility, privacy,
   cleanup, resource, and native tests before running the complete repository
   gate and bounded live acceptance.
7. Deliver P0 and P1 together on issue 51 and branch GH-51 in one ready pull
   request from current main. Use internal milestone commits if useful, keep the
   public preview rollback, report unavailable live/physical/eight-hour
   evidence as PARTIAL, and do not merge.

## DECISIONS

- Use one evolved runtime rather than parallel v1/v2 engines. Compatibility is
  a Swift decoding boundary; the helper emits v2.
- Keep the Go service as session/integration authority and Swift as observable
  presentation.
- Prefer event-driven file and process notification plus three explicit
  deadlines over polling.
- Keep the balanced default resource profile: 1% idle CPU, 75 MiB helper RSS,
  and a 120-second app-server grace.
- Do not weaken exact identity, source authority, redaction, or action
  capability rules to increase discovery count.
- Treat physical, provider, pointer-hover, 30-minute CPU, and eight-hour soak
  observations as distinct evidence; unavailable observations remain PARTIAL.
- No new Constitution rule is planned unless implementation demonstrates a
  project-wide invariant beyond feature 0011.

## DISCOVERIES

- Parsed rollout events initially retained their own path and were fed back
  into watcher admission. Under real paginated discovery this filled the
  bounded command channel and could block both live projection and owner EOF.
  Rollout evidence is now strictly one-way into session state; only app-server
  or hook seeds may request admission, and surplus hints fail boundedly.
- Inode and length checks alone do not detect a truncate-and-rewrite that
  reaches the same or greater final length. The cursor now combines file
  identity with a bounded first-record identity hash and a 4 KiB normalized
  checkpoint hash while keeping every event-loop turn within 512 KiB.
- Parsing the first 64 KiB of an oversized rollout as ordinary history could
  retain an ancient running tool whose completion lay in the skipped middle.
  Rebuild now parses only the first session-meta record for identity and uses
  the bounded tail for runtime projection.
- Codex app-server recency may be numeric seconds or milliseconds rather than
  RFC 3339. Treating an unparsed value as observed-now allowed older hints to
  displace current watchers. Recency decoding now accepts all three forms, and
  metadata-only hints cannot downgrade active watcher priority or freshness.
- A released blank hook row needed an explicit internal release marker;
  otherwise a conservative non-filtered placeholder could restart its
  two-second grace indefinitely.
- The real local run converged to four current Codex rows, including three
  processing sessions, after both startup and manual rediscovery. Watcher use
  settled at three for those active rows rather than the fixed capacity.
- Process-substitution and FIFO writers can invalidate cleanup evidence by
  retaining owner input or terminating the helper with SIGPIPE. Raw diagnostic
  output from those harness attempts was deleted; only an owner-EOF run counts
  for cleanup, and the quiet-child observation is reported separately.

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build`: PASS. The
  native compiler emits only the intentional macOS 14 deprecation warning for
  the macOS 13-compatible one-argument `onChange` overload.
- `golangci-lint run ./internal/agentsession ./internal/cli`: PASS with zero
  findings. Repository-wide lint remains PARTIAL because ten pre-existing
  config/notepad/threadstate/policy findings are outside issue 51; the one new
  fixture style finding was fixed.
- ShellCheck across local live-integration and build scripts: PASS.
- Strict codesign verification: PASS. Both `Hyperlite` and `hyperlite-cli`
  report `x86_64 arm64`.
- `kit reconcile --all --dry-run`, `kit check --project`, and `kit check
  --all`: PASS/no-op after reviewed managed refresh. The complete audit checked
  289 version-control-eligible handwritten source/test files with zero above
  300 physical lines.
- `agent-session-bridge-live.sh`: PASS, post-review run
  `20260818T175113Z-d69fa9dc`, covering private socket permissions, v2 queued
  response, disconnect retraction, metadata-only self-test, large-rollout
  convergence, replacement recovery, adaptive child cleanup, fail-open hook
  delivery, and the 20-profile inventory.
- Metadata-only live runtime result
  `20260818T170203Z-9926afea`: PASS. Startup and manual refresh produced four
  current rollout-backed rows (three processing, one recent completion), no
  fabricated action, three retained active watchers, and exact owner-run
  socket/child cleanup. The real Codex app-server child was separately absent
  after 122 quiet seconds while the helper remained alive.
- Resource smoke `20260818T175116Z-47b5379a`: PASS for 20 seconds with 32
  watchers and 100 sessions: 0.0000% sampled helper CPU, 22,560 KiB peak RSS,
  zero RSS growth, 74 descriptors, 47 threads, and fail-closed owner-EOF
  cleanup.
- Resource release acceptance: PARTIAL. The required 30-minute combined
  packaged-app/helper sample and eight-hour soak were not compressed or
  inferred. Physical pointer/display journeys and unavailable-provider smoke
  tests also remain PARTIAL.

## OUTCOME

Hyperlite now evolves its existing agent-session authority rather than running
parallel engines. A lifecycle registry owns at most 32 exact rollout watchers,
current-date directory events discover hookless sessions, and incremental
cursors recover replacement and truncation while enforcing chunk, row, and
aggregate discovery budgets. One adaptive Codex controller owns pagination,
notifications, refresh, restart, and 120-second quiet shutdown.

The memory-only domain now bounds 100 sessions, eight independent exact action
requests per session, six messages, 256 phase transitions, conservative blank
grace, explicit auxiliary filtering, exact PID/start-token exit evidence,
semantic generations, and 4 Hz ordinary projection. Metadata-only health and
on-demand self-test traverse the private runtime without provider invocation or
permission action. Swift accepts v1 and v2 for one release, emits the matching
action schema, shows current/pending requests, performs stale-only foreground
refresh, and exposes native Settings health/Verify controls.

The original failure is corrected in a real local run: current cross-process
Codex sessions appear without installed hooks. Full long-duration, physical,
and unavailable-provider evidence remains explicitly PARTIAL, so this outcome
does not claim the complete external release matrix.

## REPOSITORY MEMORY

- Decision: created
- Rationale: the resource budgets, lifecycle authorities, compatibility period,
  and clean-room tradeoffs are consequential rationale that code and tests
  alone cannot preserve.
- Artifacts: docs/specs/0012-agent-session-runtime-reliability/SPEC.md,
  docs/USER_GUIDE.md, docs/PROJECT_PROGRESS_SUMMARY.md,
  docs/references/testing.md, tests/RUN_STATUS.md, docs/CONSTITUTION.md, and
  the Kit-managed instruction support files. No feature-specific Constitution
  rule was required because feature 0011 already owns the broader ephemeral
  and event-driven invariant; the Constitution change is managed propagation
  of the independent agent-completion-output contract.
