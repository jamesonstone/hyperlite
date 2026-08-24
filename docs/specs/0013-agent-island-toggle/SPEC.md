---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0013"
  slug: agent-island-toggle
  dir: 0013-agent-island-toggle
references:
  - id: issue-53
    name: Add Agent Island toggle and active task workspace
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/53
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: agent-session-notch
    name: Agent Sessions And Notch Companion
    type: specification
    target: docs/specs/0011-agent-session-notch/SPEC.md
    relation: constrains
    read_policy: must
    used_for: presentation, privacy, action, and rollback boundaries
    status: active
  - id: agent-session-runtime-reliability
    name: Agent-Session Runtime Reliability
    type: specification
    target: docs/specs/0012-agent-session-runtime-reliability/SPEC.md
    relation: constrains
    read_policy: must
    used_for: event-driven tracking, resource bounds, and snapshot behavior
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: preference ownership, lifecycle orchestration, and view policy
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: deterministic native, packaged, and delivery evidence
    status: active
skills: []
---

# Agent Island Toggle And Agent Tasks

## PURPOSE

Let the operator disable Hyperlite's floating Agent Island without disabling
agent-session tracking. Keep current coding-agent work reachable through a
dedicated Agent Tasks workspace so Hyperlite remains useful when a persistent
top-edge companion is undesirable.

The feature must preserve Hyperlite's event-driven, bounded runtime. Turning
the island off removes presentation work; it must not add polling, timers,
transcript scans, or a parallel session engine.

## CONTEXT

Features 0011 and 0012 established one Go-owned ephemeral session authority,
one Swift observable projection, a notch/top-edge panel, and a third Sessions
workspace. The whole feature is still protected by
`HYPERLITE_AGENT_SESSIONS_PREVIEW=0`, while first-run consent controls whether
provider integrations and monitoring start.

The requested control is narrower than either existing gate. It is a durable
local presentation preference: disabling it suppresses only the floating
panel. Session discovery, lifecycle tracking, action routing, sounds, opt-in
metadata-only notifications, integration health, and the full-window workspace
continue under their existing contracts.

The existing workspace already occupies the requested position immediately
after Pinboard. Reusing and renaming it avoids duplicate navigation and state.
The wire provider is not always the user-visible client identity; for example,
Claude-compatible hooks can represent Claude Code or Cursor. Grouping therefore
uses the existing exact client profile rather than the broad provider.

## REQUIREMENTS

- R1: Add a persistent `Show Agent Island` preference backed by
  `UserDefaults` key `hyperlite.agent-island-enabled`. A missing value means
  enabled so new and existing installs default on.
- R2: Expose the preference as a native Settings switch and a dynamic Command-K
  action labeled `Turn Agent Island Off` or `Turn Agent Island On`.
- R3: The command action is present only while the overall agent-session
  preview feature is enabled. The environment rollback remains authoritative.
- R4: Changing the preference at runtime starts or stops only the owned
  notch/top-edge panel. Enabling it must not hide a regular window the operator
  already opened.
- R5: With consent and the island enabled at launch, preserve island-first
  startup. With consent and the island disabled, show the regular window on
  Dashboard. Without consent, preserve Agent Tasks onboarding regardless of
  the island preference.
- R6: Keep the existing third workspace immediately after Pinboard and rename
  all user-facing `Sessions` navigation, headings, empty states, shortcuts,
  and palette text to `Agent Tasks`. Internal enum names may remain stable.
- R7: Agent Tasks shows only non-synthetic sessions in `starting`,
  `processing`, `waitingForApproval`, `waitingForInput`, or `idle`.
  Exclude `completed`, `error`, and `ended`.
- R8: Group visible rows by exact client profile. Keep distinct profiles such
  as Claude Code and Cursor separate even when they share a provider adapter.
- R9: Order groups by unresolved attention, then active work, then idle, with
  the user-visible client name as a deterministic tie-breaker. Preserve the
  session store's established order within a group.
- R10: Do not change the notch's own projection, session wire schemas, Go
  helper, provider integrations, snapshot generation, consent, sounds,
  notifications, action capabilities, or routing persistence.
- R11: Introduce no polling, continuous animation, recurring background work,
  or additional long-running child process. Preference changes and projections
  are event-driven and bounded by the existing 100-row snapshot.
- R12: Use macOS-native toggle, command, section, keyboard, and VoiceOver
  semantics and preserve macOS 13 universal compatibility.
- R13: Keep every handwritten source and test file at 300 physical lines or
  fewer.

Observable acceptance:

- A clean preference store and a store without the key both report the island
  enabled; an explicit false persists across a new preference owner.
- Runtime preference changes affect only panel ownership and preserve an open
  regular window.
- The launch destination follows R5 for all consent/preference combinations.
- Workspace order remains Dashboard, Pinboard, Agent Tasks.
- Mixed snapshots prove terminal and synthetic rows are absent and same-
  provider/different-profile rows are grouped separately.
- The complete repository validation gate passes. Additional soak testing is
  intentionally not required for this presentation-only feature.

## ACCEPTED PLAN

1. Add a small injectable observable preference owner rather than expanding the
   near-limit session state. Keep persistence at the macOS composition boundary.
2. Add pure launch and Agent Tasks presentation policies so consent/preference
   decisions, live filtering, grouping, and ordering are deterministic without
   AppKit or process dependencies.
3. Combine integration consent with the preference in application lifecycle.
   Start the panel only when both are true, choose the accepted launch
   destination once, and keep runtime toggles from hiding an open window.
4. Inject the preference into the regular window, Settings, and command
   palette. Add the native switch and dynamic action using existing interaction
   patterns.
5. Rename the existing user-facing Sessions workspace to Agent Tasks and render
   the pure grouped live projection. Keep the internal workspace case if that
   minimizes compatibility risk.
6. Add focused preference, policy, palette, workspace, accessibility, and
   lifecycle coverage. Update the user guide, testing reference, run-status map
   only when its current state changes, and progress summary.
7. Run the complete code-level, macOS, packaging, source-size, signing, and
   architecture gates. Deliver one ready PR from issue 53 without merging.

## DECISIONS

- The switch controls only the floating island. It is not a second integration
  consent control and not a substitute for the full environment rollback.
- Agent Tasks is the renamed existing third workspace, not a duplicate fourth
  tab.
- The workspace shows live work only. Terminal rows remain available to the
  existing notch/session runtime for its bounded completion behavior but do
  not appear in Agent Tasks.
- Client profile is the grouping authority because provider adapter identity
  is too broad for the requested user-facing grouping.
- Default-on is represented by absence-compatible decoding rather than writing
  a migration value for every existing install.
- A single supervisor lane owns implementation because the changes share one
  Swift navigation/lifecycle contract and the active host does not authorize
  subagent creation without an explicit user request.
- No new Constitution rule is planned; features 0011 and 0012 already preserve
  the project-wide separation and resource invariants this work follows.

## DISCOVERIES

- The existing workspace is already third after Pinboard, so no navigation
  insertion is necessary.
- Current Agent Sessions filtering removes synthetic rows only; a new pure
  live projection is required to prevent retained completion and error rows
  from appearing.
- Current lifecycle observes consent alone and hides the regular window when
  consent becomes true; the new preference must be composed there so a runtime
  enable never unexpectedly dismisses user-visible work.
- `HyperliteFeatureFlags.agentSessionPresentation` already implements the
  complete environment rollback and remains unchanged.
- The notch coordinator historically started the session helper as a side
  effect. Lifecycle now starts tracking directly from consent before deciding
  whether the panel should exist, so an off preference cannot disable
  discovery.
- The selected Swift toolchain requires explicit returns in the phase
  visibility switch; the final policy retains exhaustive phase handling while
  remaining compatible with the macOS 13 build toolchain.

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build`: PASS. Go
  formatting, vet, unit/race suites, CLI build, complete native type-check,
  executable Swift model tests, and universal app packaging passed. The only
  compiler warnings are the existing macOS 14 `onChange` deprecations retained
  for macOS 13 compatibility.
- Focused Agent Island tests: PASS for missing-key default-on behavior without
  migration writes, persisted on/off state, all launch destinations, tracking
  independent of presentation, live/terminal/synthetic filtering, exact client
  grouping, group priority, row order, workspace order, and dynamic palette
  labels.
- `codesign --verify --deep --strict build/Hyperlite.app`: PASS. `plutil -lint`
  passed for the packaged Info.plist.
- `lipo -archs` reported `x86_64 arm64` for both `Hyperlite` and
  `hyperlite-cli`.
- `kit check --project`, `kit check --all`, and the final
  `kit reconcile --all --dry-run`: PASS/no-op after the two reviewed managed
  refresh waves requested by the user.
- Whole-project source-size audit: PASS; 297 eligible handwritten source/test
  files checked and zero exceed 300 physical lines.
- `git diff --check`: PASS after final curation.
- Additional soak testing: SKIPPED by explicit user direction. This feature
  adds no timer, watcher, polling loop, helper protocol, or child process, so it
  does not replace the still-PARTIAL long-duration evidence recorded by 0012.

## OUTCOME

Hyperlite now owns one default-on, persisted Agent Island presentation
preference exposed through native Settings and a dynamic Command-K action.
Disabling it closes the floating panel on every display but keeps the existing
consent-gated helper, hooks, watchers, alerts, actions, and snapshot state
running. A consented launch with the island disabled opens Dashboard; island-
first launch and first-run onboarding retain their existing behavior.

The third workspace is now presented as Agent Tasks. It derives only live,
non-synthetic rows from the existing bounded snapshot and groups them by exact
client profile with attention, active, then idle priority. Terminal rows remain
available to the unchanged notch/runtime retention contract but do not appear
in the full-window task list. No Go protocol, persistence, provider, or runtime
resource boundary changed.

## REPOSITORY MEMORY

- Decision: created
- Rationale: the distinction among integration consent, full preview rollback,
  floating presentation, launch behavior, and live workspace membership is
  material product rationale not recoverable from individual code paths alone.
  No feature-specific Constitution addition is warranted because 0011/0012
  already own the broader ephemeral and event-driven invariants.
- Artifacts: `docs/specs/0013-agent-island-toggle/SPEC.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`, `docs/USER_GUIDE.md`,
  `docs/references/testing.md`, and `README.md`. The Constitution and managed
  instruction files changed only through the separately requested Kit refresh.
