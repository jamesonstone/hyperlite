---
kit_metadata_version: 1
artifact: "spec"
workflow_version: 3
phase: "deliver"
delivery_intent: "ready_pull_request"
feature:
  id: "0011"
  slug: "agent-session-notch"
  dir: "0011-agent-session-notch"
references:
  - id: issue-47
    name: Add agent sessions and notch companion
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/47
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: ping-island-baseline
    name: Ping Island session architecture baseline
    type: external-reference
    target: https://github.com/erha19/ping-island/tree/6ec8e77e71406bd39823707a3795a15539964f74
    relation: informs
    read_policy: evidence
    used_for: clean-room provider and session architecture research
    status: active
  - id: codex-app-server
    name: Codex App Server
    type: external-reference
    target: https://learn.chatgpt.com/docs/app-server
    relation: informs
    read_policy: evidence
    used_for: documented local Codex transport and thread contracts
    status: active
  - id: apple-hig-typography
    name: Apple Human Interface Guidelines Typography
    type: external-reference
    target: https://developer.apple.com/design/human-interface-guidelines/typography
    relation: informs
    read_policy: evidence
    used_for: native macOS hierarchy, system chrome, and minimum legibility
    status: active
  - id: apple-hig-popovers
    name: Apple Human Interface Guidelines Popovers
    type: external-reference
    target: https://developer.apple.com/design/human-interface-guidelines/popovers
    relation: informs
    read_policy: evidence
    used_for: notch companion interaction and transient-content boundaries
    status: active
skills: []
---
# Agent Sessions And Notch Companion

## PURPOSE

Hyperlite should provide a compact, native view of live local coding-agent
sessions at the Mac notch or top edge. It should surface requests that need the
operator, allow only exact provider-supported responses, and open a larger
Sessions workspace without turning runtime agent events into project evidence
or durable task state.

## CONTEXT

Hyperlite currently owns a regular SwiftUI window, a menu-bar affordance, a
bounded Go helper, and independent project, pull-request, note, Pinboard, and
pinned-Codex projections. Its project scanner deliberately avoids continuous
background work, and pinned Codex membership is a separate read-only Desktop
projection.

Ping Island demonstrates a useful clean-room architecture: provider ingress is
normalized into a serialized session store and then projected into compact and
expanded native views. Its fixed-port Codex WebSocket transport is not suitable
for Hyperlite because OpenAI documents WebSocket app-server transport as
experimental and unsupported. Hyperlite instead uses the documented stdio
transport and treats hook or bounded rollout evidence as the cross-process
fallback.

This feature materially changes application lifecycle, local integration
configuration, action authority, privacy, and native presentation. It therefore
requires durable rationale and a separate runtime boundary from inferred
threads and pinned Codex membership.

## REQUIREMENTS

- R1: Track the accepted local provider matrix: Claude Code; Codex app, CLI,
  and subagents; Gemini CLI; Antigravity CLI; Hermes; Pi; Qwen Code; Kimi;
  OpenClaw; OpenCode; Cursor; Qoder, Qoder CN, Qoder CLI, Qoder CN CLI, and
  QoderWork; CodeBuddy, CodeBuddy CLI, and WorkBuddy; and GitHub Copilot.
- R2: Keep live sessions, pinned Codex membership, inferred project threads,
  project attention, notes, and Pinboard state as separate projections.
- R3: Use exact provider plus stable session identity. Merge ingress aliases or
  subagents only from explicit provider relationships or exact rollout
  identity, never from working-directory or timestamp heuristics.
- R4: Normalize session phases as starting, processing, waiting for approval,
  waiting for input, idle, completed, error, and ended. Sort unresolved
  attention first, active work second, and recent terminal state last.
- R5: Keep completed sessions visible for ten minutes and expire every
  non-attention session after thirty minutes without activity. Never
  age-expire unresolved attention. Retain routing-only associations for at most
  twenty-four hours.
- R6: Use event-driven hooks, app-server notifications, and tracked-file
  changes after one bounded launch or foreground discovery. Use one
  next-deadline timer for expiry and no continuous UI timeline or project scan.
- R7: Use Codex app-server stdio with the documented initialize and initialized
  handshake. Treat notLoaded as unknown cross-process runtime state, never as
  authoritative idle.
- R8: Present a centered first-run welcome state with Enable Recommended,
  Review in Settings, and Not Now choices. Recommended includes detected
  clients only. Do not start provider monitoring or app-server discovery before
  explicit consent. After consent,
  maintain only exact Hyperlite-owned entries while preserving unrelated
  configuration and failing closed on malformed, symlinked, oversized,
  wrong-owner, or concurrently changed inputs.
- R9: Normalize and redact before session state. Never persist or emit raw hook
  payloads, prompts, replies, transcripts, reasoning, arbitrary tool output,
  secrets, environment data, content-bearing telemetry, or content-bearing
  diagnostics.
- R10: The collapsed notch contains metadata only. An explicitly opened
  session may hold six recent displayable user or assistant messages capped at
  2,000 characters each, a latest final result capped at 8,000 characters, and
  a decision payload capped at 8,000 characters. All content is memory-only.
- R11: Approval or reply controls require the exact current session ID,
  request ID, revision, live response channel, and complete decision-critical
  context. Redacted, truncated, stale, unsupported, or rollout-only requests
  offer Open in Client instead.
- R12: Allow Once, Deny, and Answer are capability-gated and single-submit.
  Session-wide or automatic permission requires a separate confirmation,
  exact provider-native scope, visible active state, provider-native
  revocation, and automatic clearing at session end. Never simulate scope by
  repeatedly approving individual requests.
- R13: Add a borderless nonactivating top-center panel that uses macOS safe-area
  APIs on notch displays and becomes a centered top-edge pill otherwise.
  Respect Reduce Motion and avoid continuous animation.
- R14: Launch notch-first after onboarding while retaining the regular Dock
  app, menu-bar fallback, global hotkey, and dashboard. Add a third Sessions
  workspace backed by the same state.
- R15: Sounds and native notifications are opt-in and metadata-only. Request
  Accessibility or Apple Events permission only when the operator invokes a
  focus route that needs it.
- R16: Keep every handwritten source and test file at 300 physical lines or
  fewer and preserve the macOS 13 arm64/x86_64 universal build.
- R17: New agent-session chrome, controls, lists, and status text use native
  macOS system typography at legible sizes. Technical messages, paths,
  arguments, commands, and results retain the shared monospaced resolver.
- R18: Ordinary hover never opens the companion. Click expands it, and a newly
  urgent approval or input request may expand once. Hover, focus, typing, or
  control interaction prevents timed collapse.
- R19: Keep the expanded companion as a bounded mini workspace. Ongoing
  integration management lives in grouped Settings, with a Sessions shortcut.
  The new surfaces inherit Hyperlite's existing dark application appearance
  while using semantic macOS materials, controls, selection, and action roles.
- R20: Presentation reacts to exact state transitions rather than repeatedly
  presenting retained attention or terminal rows. Pending actions submit once,
  answer state follows the exact request revision, and partial integration
  updates converge to observed provider state.

Default-activation acceptance:

- With `HYPERLITE_AGENT_SESSIONS_PREVIEW` absent, the Sessions workspace and
  notch or top-edge companion are enabled.
- `HYPERLITE_AGENT_SESSIONS_PREVIEW=0` is an explicit local rollback that
  suppresses the session presentation.
- Default activation does not bypass first-run integration consent, grant an
  action capability, or claim unobserved provider or physical-notch evidence.
- Before consent, the app may perform an explicit bounded integration-detection
  request for onboarding, but it does not launch the long-running session
  service, provider hooks, rollout watchers, or Codex app server.
- Session rows and actions are keyboard- and VoiceOver-operable, interface text
  remains at least ten points, and ordinary hover does not expand the panel.
- New attention and terminal transitions present at most once per exact event;
  active user interaction cancels pending dismissal.

Full provider-parity acceptance remains tracked as residual evidence:

- Every advertised provider passes its contract, configuration round-trip,
  lifecycle smoke, and required real response test.
- Exact stale action requests fail without changing the provider session.
- Disabling an integration removes only Hyperlite-owned material and clears
  its routing associations.
- Synthetic secrets do not appear in any Hyperlite persistence, diagnostics,
  telemetry, notification, or snapshot artifact.
- Physical-notch and notchless or external-display interaction both pass,
  including fullscreen, sleep/wake, hit testing, and display migration.

Non-goals: remote SSH monitoring, floating companions, mascots, full transcript
indexing, cloud-agent inspection, automatic project-state inference from agent
events, provider emulation, copied Ping Island code or assets, and support for
future Ping Island clients not present at the frozen baseline.

## ACCEPTED PLAN

1. Add a versioned session protocol and a Go session domain with exact
   identity, source precedence, redaction, bounded display content, liveness,
   expiry, action revision checks, and routing-only persistence.
2. Add an app-owned long-running helper command with JSON Lines over process
   pipes and a user-only Unix socket for hook delivery. Bound restart and
   guarantee exact owned-process cleanup.
3. Add a declarative provider registry, safe detected-client onboarding, and
   format-specific owned-entry reconciliation for JSON, TOML, generated plugin,
   hook-directory, extension, and Copilot integrations.
4. Add a documented-stdio Codex adapter plus bounded rollout-tail fallback.
   Prefer exact live response channels over cross-process file evidence.
5. Add Swift decoding and observable orchestration, the notch or top-edge
   panel, metadata-only compact state, bounded expanded detail, capability-
   gated actions, integration settings, and a full Sessions workspace.
6. Add deterministic Go and Swift tests, temporary-home installer integration
   tests, a local socket round trip, secret-leak inspection, complete build
   gates, and literal provider and hardware acceptance evidence.
7. Enable the preview by default after deterministic contract, privacy,
   process-ownership, top-edge, and synthetic response validation. Preserve an
   explicit environment rollback and report missing provider or physical-notch
   proof as residual evidence rather than silently claiming full parity.
8. Refine the native presentation without redesigning Dashboard or Pinboard:
   move integration management to Settings, use native system chrome with
   monospaced technical content, retain the notch mini workspace, gate service
   startup on consent, and repair verified transition, process, routing, and
   privacy defects before delivery.

## DECISIONS

- Keep Go as the session and integration authority and Swift as the native
  projection, matching Hyperlite's existing helper boundary.
- Use app-server stdio and reject the researched fixed-port WebSocket design.
- Prefer exact duplicate visibility over a false heuristic merge.
- Keep the existing pinned-Codex reader authoritative for pin membership; app-
  server pin metadata does not supersede feature 0007 in this work.
- Keep routing metadata for twenty-four hours but keep all user and agent
  content ephemeral.
- Ship one complete pull request rather than progressively advertising partial
  provider support.
- On 2026-08-17, the user explicitly superseded the external-evidence release
  gate and requested default activation. An absent preview variable now enables
  the surface, while exact `0` disables it. First-run provider configuration
  still requires consent, and unavailable live evidence remains reported.
- On 2026-08-17, the user accepted a macOS-native refinement limited visually
  to the new session surfaces while authorizing correctness repairs across the
  full feature. The companion remains notch-first and keeps its mini-workspace;
  it opens by click or newly urgent attention, never ordinary hover. Provider
  settings move to the Settings scene. Physical-notch interaction is not a
  delivery gate for this pass and remains explicitly unverified.

## DISCOVERIES

- Empty Go slices must remain empty JSON arrays at the Swift boundary; cloning
  through a nil slice produced `messages: null` and would have broken native
  decoding. The wire contract now has regression coverage.
- Closing the owning app's stdin originally left the helper alive because a
  clean scanner EOF was ignored. EOF now ends the service, cancels the Codex
  child context, closes response sockets, and removes the runtime socket.
- A blocking provider can disconnect before the operator responds. The service
  now observes the full-duplex connection and retracts the exact pending action
  immediately instead of retaining immortal attention.
- A fixed 460-point expanded panel was wasteful when no sessions existed. The
  top-edge surface now uses a compact 150-point empty state while preserving
  the full bounded detail size when sessions exist.
- The available local screens are both notchless (`safeAreaInsets.top == 0`),
  so the centered top-edge fallback could be inspected but physical-notch
  acceptance cannot be produced in this environment.
- Local detection currently finds Claude Code, Codex, Gemini CLI, and GitHub
  Copilot. The remaining frozen profiles are not installed, so their mandatory
  real lifecycle/action evidence remains unavailable.
- The first implementation started the long-running service and Codex app
  server before first-run consent. Onboarding now uses a bounded detection-only
  command, and monitoring starts only after Enable Recommended, Start Agent
  Sessions, or Not Now records an explicit choice.
- The initial rollout watcher could synchronously send back into its owning
  service loop, and Darwin cancellation closed a kqueue from a competing
  goroutine. Initial emission is now asynchronous, every background error send
  is cancellation-aware, and a user event wakes a single-owner kqueue loop.
- Lexical rollout containment and absent-config replacement did not defend
  intermediate symlinks or create-time races. Resolved-path confinement and
  atomic create-if-absent writes now fail closed with focused regression tests.
- The original seven-to-nine-point monospaced session UI was below the native
  macOS legibility floor and relied on tap or hover semantics. Native lists,
  system chrome typography, monospaced technical content, explicit buttons,
  and VoiceOver labels now preserve the accepted dark Hyperlite identity while
  behaving like a Mac utility.

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build`: passed for
  the corrected Go service, native Swift refactor, and universal bundle after
  integration. macOS 14 `onChange` deprecation warnings remain intentionally
  because the replacement overload is unavailable to the macOS 13 target.
- `tests/live-integration/local/agent-session-bridge-live.sh`: PASS, run
  `20260817T202936Z-6da99a7a`, for raw-object metadata allowlisting, private
  socket permissions, exact action round trip, disconnect retraction, owner EOF
  cleanup including Codex child termination, fail-open delivery, and the
  metadata-only twenty-profile inventory.
- `golangci-lint run ./internal/agentsession ./internal/cli`: passed with zero
  issues. Darwin watcher tests passed one hundred consecutive runs; supported
  cross-build checks and ShellCheck passed.
- `codesign --verify --deep --strict build/Hyperlite.app`: passed.
- `lipo -archs` for both native executables: `x86_64 arm64`.
- Complete affected-source/test audit: every handwritten file is at most 300
  physical lines.
- Packaged Computer Use inspection: centered native onboarding, no helper
  before consent, notchless compact/expanded surfaces, consented helper start,
  native empty Sessions state, Settings-owned provider controls with exact
  VoiceOver labels/hints/values, and exact process cleanup passed. Evidence:
  `tmp/2026-08-17/agent-session-ui-manual/4/`.
- Provider/display acceptance: PARTIAL. Physical-notch hardware and real smoke
  evidence for every frozen provider remain unavailable. Per the explicit
  activation decision, this limits the full-parity evidence claim but no longer
  disables the preview by default.
- `kit check --project`, `kit check --all`, and the no-op reconcile audit:
  passed. The whole-project source-size audit checked 250 eligible handwritten
  source/test files with zero violations.

## OUTCOME

Hyperlite now contains a clean-room, default-on agent-session surface. A Go
authority owns the versioned protocol, exact session store, provider registry,
safe integration reconciliation, private socket, Codex stdio discovery,
bounded rollout tails, redaction, actions, expiry, and routing-only state. The
native app adds consent-gated startup, centered onboarding, Settings-owned
integration health, a keyboard-accessible Sessions workspace, metadata-only
alerts, a click/new-urgent notch or top-edge mini workspace, and exact
single-submit capability-gated controls.

With `HYPERLITE_AGENT_SESSIONS_PREVIEW` absent, the surface is enabled;
`HYPERLITE_AGENT_SESSIONS_PREVIEW=0` provides an explicit local rollback. The
first-run consent boundary and provider-native action authority remain intact.
External provider and physical-notch evidence is still PARTIAL, so the outcome
does not claim complete live-validated Ping parity.

## REPOSITORY MEMORY

- Decision: updated
- Rationale: source authority, permission semantics, privacy limits, provider
  boundaries, lifecycle, and notch behavior are material rationale that code
  and tests alone cannot preserve.
- Artifacts: `docs/specs/0011-agent-session-notch/SPEC.md`,
  `docs/CONSTITUTION.md`, `docs/PROJECT_PROGRESS_SUMMARY.md`,
  `docs/references/testing.md`, `docs/USER_GUIDE.md`, `README.md`, and
  `tests/RUN_STATUS.md`.
