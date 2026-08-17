---
kit_metadata_version: 1
artifact: "spec"
workflow_version: 3
phase: "validate"
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
- R8: Present first-run Enable Recommended Integrations, Customize, and Skip
  choices. Recommended includes detected clients only. After consent,
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

Observable acceptance:

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
7. Keep the feature disabled until the full frozen provider matrix and both
   display modes satisfy their release gates, then deliver all work through one
   ready pull request.

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

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build`: passed for
  the integrated Go, native Swift, and universal bundle before final curation;
  macOS 14 deprecation warnings remain the pre-existing compatibility form.
- `tests/live-integration/local/agent-session-bridge-live.sh`: PASS, run
  `20260817T175432Z-0ee2f48d`, for private
  socket permissions, exact action round trip, disconnect retraction, owner EOF
  cleanup including Codex child termination, fail-open delivery, and the
  metadata-only twenty-profile inventory.
- `codesign --verify --deep --strict build/Hyperlite.app`: passed.
- `lipo -archs` for both native executables: `x86_64 arm64`.
- Complete affected-source/test audit: every handwritten file is at most 300
  physical lines.
- Packaged Computer Use inspection: top-edge compact/expanded UI, accessibility
  tree, consent screen, exact synthetic Claude-compatible approval, 12-second
  attention collapse with retained badge, provider response, Processing
  transition, Open Hyperlite handoff, and exact process cleanup passed.
- Provider/display acceptance: PARTIAL. Physical-notch hardware and real smoke
  evidence for every frozen provider remain blocked and prevent release
  enablement.
- `kit check agent-session-notch`: passed. `kit check --project`: failed with
  twelve instruction/registry drift findings that reproduce exactly on the
  untouched primary `origin/main` checkout and are outside this feature.

## OUTCOME

Hyperlite now contains a clean-room, release-gated agent-session preview. A Go
authority owns the versioned protocol, exact session store, provider registry,
safe integration reconciliation, private socket, Codex stdio discovery,
bounded rollout tails, redaction, actions, expiry, and routing-only state. The
native app adds consent/customization, a Sessions workspace, metadata-only
alerts, a notch or top-edge companion, and exact capability-gated controls.

The feature remains disabled by default through
`HYPERLITE_AGENT_SESSIONS_PREVIEW=1`. This is intentional: the accepted release
contract requires live proof for every frozen provider and both physical-notch
and notchless displays. Those external acceptance gates are not available in
the current environment, so the release outcome is PARTIAL rather than a
claim of complete Ping-parity support.

## REPOSITORY MEMORY

- Decision: created
- Rationale: source authority, permission semantics, privacy limits, provider
  boundaries, lifecycle, and notch behavior are material rationale that code
  and tests alone cannot preserve.
- Artifacts: `docs/specs/0011-agent-session-notch/SPEC.md`,
  `docs/CONSTITUTION.md`, `docs/PROJECT_PROGRESS_SUMMARY.md`,
  `docs/references/testing.md`, `docs/USER_GUIDE.md`, `README.md`, and
  `tests/RUN_STATUS.md`.
