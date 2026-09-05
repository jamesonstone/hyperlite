---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0016"
  slug: remove-agent-island
  dir: 0016-remove-agent-island
references:
  - id: issue-62
    name: Remove the Agent Island / notch companion
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/62
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: agent-session-notch
    name: Agent Sessions And Notch Companion
    type: specification
    target: docs/specs/0011-agent-session-notch/SPEC.md
    relation: supersedes
    read_policy: evidence
    used_for: withdrawn notch companion presentation
    status: active
  - id: agent-island-toggle
    name: Agent Island Toggle And Agent Tasks
    type: specification
    target: docs/specs/0013-agent-island-toggle/SPEC.md
    relation: supersedes
    read_policy: evidence
    used_for: withdrawn island preference; retained Agent Tasks workspace
    status: active
  - id: agent-session-runtime-reliability
    name: Agent-Session Runtime Reliability
    type: specification
    target: docs/specs/0012-agent-session-runtime-reliability/SPEC.md
    relation: constrains
    read_policy: must
    used_for: idle CPU bounds and event-driven tracking
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: lifecycle orchestration and presentation ownership
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: native presentation tests
    status: active
skills: []
---
# Remove Agent Island

## PURPOSE

Remove Hyperlite's floating Agent Island / notch companion. It was not useful
and it pegged a CPU core for days in a SwiftUI layout loop. Keep Agent Tasks
and event-driven session tracking in the regular window.

## CONTEXT

Features 0011 and 0013 added a persistent top-edge `NSPanel` hosting SwiftUI,
sized from `NSScreen` safe-area and auxiliary menu-bar regions, and optionally
hid the main window on launch. On a notched MacBook that panel sat in a
geometry feedback loop: `didChangeScreenParametersNotification` resized the
panel, occupying the notch changed those metrics, and `NSHostingView` never
left `sizeThatFits`. A live sample of PID 1287 showed ~100% main-thread CPU
for 5.5 days.

The operator asked to delete the island rather than patch the loop. Session
discovery, consent, Settings integrations, sounds, notifications, and the
Agent Tasks workspace remain.

## REQUIREMENTS

- R1: Do not create, show, or retain a notch, top-edge, or Agent Island panel.
- R2: Do not expose `Show Agent Island`, `Turn Agent Island On`, or
  `Turn Agent Island Off`. Ignore leftover `hyperlite.agent-island-enabled`.
- R3: Consented launches open the regular Hyperlite window on Dashboard.
  Unconsented launches still open Agent Tasks onboarding. Never order the
  main window out for an island.
- R4: Keep Agent Tasks as the third workspace, Command-3, and Command-K
  `Show Agent Tasks`. Do not change Go session authority, snapshot schemas,
  integrations, or consent.
- R5: Introduce no replacement floating companion, continuous animation, or
  screen-parameter observer.

## ACCEPTED PLAN

1. Delete the notch panel, notch view, notch geometry, island preference, and
   their focused tests.
2. Replace consent/preference launch destinations with Dashboard versus Agent
   Tasks onboarding only, and always order the main window front.
3. Remove the Settings toggle and Command-K island action. Ignore leftover
   `hyperlite.agent-island-enabled`.
4. Keep Agent Tasks, session tracking, consent, integrations, sounds, and
   notifications in the regular window.
5. Document the withdrawal in this spec, the user guide, README, testing
   reference, and progress summary. Deliver one ready PR from issue 62.

## DECISIONS

- Topology: `single-lane, because tightly coupled`. Panel lifecycle, launch
  destination, Settings, and Command-K shared one presentation contract.
- Delete the companion instead of patching the layout loop. The operator
  judged the island not useful; a narrower geometry fix would keep the
  unused surface.
- Do not migrate or keep reading `hyperlite.agent-island-enabled`. A leftover
  key is inert.
- Features 0011 and 0013 remain historical. This feature supersedes their
  companion and preference requirements; Agent Tasks membership, grouping,
  and session runtime stay in force.
- Snapshot `popupTransition` stays as session-model policy. It no longer
  drives a floating panel.

## DISCOVERIES

- The 5.5-day 100% CPU sample was `NSHostingView` layout, not session work.
  Occupying the notch could change `safeAreaInsets` and auxiliary menu-bar
  metrics, which fired `didChangeScreenParametersNotification`, which resized
  the panel again.
- Island-first launch ordered the main window out. After removal, every
  launch path shows the regular window.
- Agent Tasks was already the third workspace. Removal does not insert or
  rename navigation.

## VALIDATION

- `make fmt-check vet test macos-test macos-build`: PASS. Go formatting, vet,
  and unit tests plus native type-check, executable Swift model tests, and
  universal app packaging passed. The only compiler warnings are the existing
  macOS 14 `onChange` deprecations retained for macOS 13 compatibility.
- Focused launch and Command-K tests: PASS for Dashboard/onboarding
  destinations, consent-gated tracking without an island destination, and
  absence of `action:toggle-agent-island`.
- `codesign --verify --deep --strict build/Hyperlite.app`: PASS. `plutil -lint`
  passed for the packaged Info.plist.
- `lipo -archs` reported `x86_64 arm64` for both `Hyperlite` and
  `hyperlite-cli`.
- `kit check --project` and `kit check --all`: PASS after the required spec
  sections were added. `kit reconcile --all --dry-run` still reports planned
  managed-file refreshes unrelated to this feature; those were not applied.
- Whole-project source-size audit: PASS; `source-file-size audit: complete
  (387 version-control-eligible candidates; 299 eligible handwritten
  source/test files checked; 0 above 300 physical lines)`.
- `git diff --check`: PASS.
- Live window click-through: SKIPPED to avoid launching or replacing a
  running operator instance. Absence of notch panel, Settings toggle, and
  Command-K island actions is covered by source deletion and executable
  Swift tests.

## OUTCOME

Hyperlite no longer creates a notch, top-edge, or Agent Island panel. Settings
and Command-K have no island preference. Consented launches open the regular
window on Dashboard; unconsented launches still open Agent Tasks onboarding
and still show that window.

Agent Tasks, consent, integrations, sounds, notifications, and the Go session
helper remain. Leftover `hyperlite.agent-island-enabled` is ignored.

## REPOSITORY MEMORY

- Decision: created
- Rationale: withdrawing the unused companion after the layout-loop CPU peg,
  rather than patching panel geometry, is product intent that tests cannot
  preserve. Features 0011 and 0013 stay as history; this feature is the
  current companion contract.
- Artifacts: `docs/specs/0016-remove-agent-island/SPEC.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`, `docs/USER_GUIDE.md`,
  `docs/references/testing.md`, and `README.md`. Constitution unchanged.
