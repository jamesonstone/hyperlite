---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: 0001
  slug: standalone-hyperlite
  dir: 0001-standalone-hyperlite
references:
  - id: issue-1
    name: Establish Hyperlite as a standalone application
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/1
    relation: implements
    read_policy: must
    used_for: product extraction scope and acceptance criteria
    status: active
---

# Standalone Hyperlite

## PURPOSE

Hyperlite is a fast, independent macOS attention window for active local Git
work and authored pull requests. It answers what needs attention without
starting Beacon or retaining Beacon runtime state.

## CONTEXT

The former Hyperlite target lived inside Beacon and bundled a compatibility
scanner named `bctl`. That coupling meant its lifecycle, packaging, and
configuration were tied to the larger Beacon application. Hyperlite now owns a
small direct scanner, a native window, and its own command-line entrypoint.

## REQUIREMENTS

- Ship the `hyperlite` CLI and `Hyperlite.app` from this repository without
  importing, launching, or packaging Beacon.
- On first use, copy an existing `~/.config/beacon/config.yaml` byte-for-byte
  into `~/.config/hyperlite/config.yaml` when the latter does not exist; never
  overwrite the Hyperlite-owned file.
- Scan only configured projects and report actionable local worktrees,
  changed main-branch work, and open authored pull requests.
- Keep the native surface lightweight: initial local scan avoids network work;
  explicit refresh uses normal scanner execution. Feature
  `0018-runtime-resource-cut` superseded hotkey-triggered refresh: the
  Control+Shift+H global hotkey shows the window and does not force GitHub
  work.
- Retain a visible window, a compact count in the menu bar, hotkey settings,
  hover descriptions, and direct evidence actions.
- Present active coordination regardless of age and omit completed or dormant
  projections from the primary interface.
- Provide `make hyper`, which stops a prior Hyperlite process before opening
  the freshly built application.

Non-goals: Beacon dashboard functionality, a background scanner, task timing,
Git history mutation, or automatic configuration overwrite.

## ACCEPTED PLAN

1. Copy the scanner primitives needed for direct project discovery, Git facts,
   and authored pull-request lookup into Hyperlite under its own Go module.
2. Replace the old compatibility command with a compact `hyperlite` CLI and a
   Hyperlite-owned configuration migration boundary.
3. Build a regular SwiftUI window and menu-bar entry around that CLI's JSON
   output, with hotkey-triggered focus. Feature `0018-runtime-resource-cut`
   removed hotkey-triggered GitHub refresh.
4. Remove the migrated command, app target, packaging, and documentation from
   Beacon in a separate, dependent delivery.

## DECISIONS

- Hyperlite uses direct, bounded CLI scans rather than Beacon's background
  agent or cache. This makes process ownership and refresh behavior explicit.
- The migration is copy-once and preserves contents exactly. Hyperlite never
  reads Beacon's config as its ongoing source of truth after initialization.
- A standard window is the primary interaction surface; the menu bar provides
  a compact launch/count affordance, not the only way to find the app.
- The original rocket and distinct-project count were the standalone launch
  identity. On 2026-07-27, feature `0002-command-palettes` superseded that
  visual with the liquid-metal ghost identity and changed the menu-bar value to
  the number of attention work items; the compact launch affordance remains.
- The scanner remains read-only. It uses local Git facts and `gh` only to list
  open pull requests, preserving the small, inspectable status model.
- On 2026-07-28, feature `0003-inferred-attention` superseded the flat
  work-item model and universal age filter. Hyperlite now reconstructs
  evidence-backed goal threads, keeps active threads visible regardless of
  age, and omits inactive projections from the primary attention surface while
  retaining them in private state and scan output for continuity.
- On 2026-09-05, feature `0018-runtime-resource-cut` superseded hotkey-triggered
  complete scan. The global hotkey shows the window; GitHub refresh remains
  startup or foreground staleness plus explicit Refresh.

## DISCOVERIES

- A local-first scan needs an explicit no-network mode: `--local` skips GitHub
  pull-request lookup as well as `git fetch`. The refresh control uses the
  complete scan. Feature `0018-runtime-resource-cut` superseded hotkey use of
  that complete scan.
- macOS filesystems are commonly case-insensitive, so the app executable
  `Hyperlite` cannot safely coexist with a bundled helper named `hyperlite`.
  The bundle uses `hyperlite-cli` while the public executable remains
  `hyperlite`.
- A menu-only SwiftUI scene exits after launch. A regular `WindowGroup` plus a
  close-to-hide window delegate retains the window target for the global hotkey
  without making the menu bar the only way to find the app.

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build` passed.
- The configuration migration test proves exact first-copy contents and that
  an existing Hyperlite config is never overwritten.
- A live `hyperlite --json --local --no-refresh` scan created an exact copy of
  the existing Beacon config at `~/.config/hyperlite/config.yaml`.
- The packaged helper passed `hyperlite version`, is universal (`arm64` and
  `x86_64`), and the app bundle passed strict code-signature verification.
- `make hyper` replaced a live Hyperlite app process and launched exactly one
  new windowed app process.

## OUTCOME

Hyperlite now lives in its own Go module and native app bundle. It owns the
`hyperlite` command, one-time config migration, direct scanner primitives, a
windowed attention-thread experience, compact menu count, hover details, and
evidence actions. It neither imports nor starts Beacon.

## REPOSITORY MEMORY

Decision: created.

Rationale: the standalone ownership boundary, configuration migration rule,
and deliberately narrow status model are durable product decisions that code
alone cannot fully convey.

Artifacts: `docs/specs/0001-standalone-hyperlite/SPEC.md`.
