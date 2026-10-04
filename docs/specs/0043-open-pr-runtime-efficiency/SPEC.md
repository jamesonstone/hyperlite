---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0043"
  slug: open-pr-runtime-efficiency
  dir: 0043-open-pr-runtime-efficiency
references:
  - id: issue-136
    name: "Open PRs window hangs with a beach ball on large pull request lists"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/136
    relation: implements
    read_policy: must
    used_for: hang evidence, scope, and acceptance
    status: active
  - id: open-pr-fetch-reliability
    name: Open PR Fetch Reliability
    type: specification
    target: docs/specs/0037-open-pr-fetch-reliability/SPEC.md
    relation: informs
    read_policy: conditional
    used_for: discovery and refresh behavior this reduces in cost
    status: active
skills: []
---

# Open PR Runtime Efficiency

## PURPOSE

Stop the Open PRs window from hanging and make Hyperlite spend as little CPU,
memory, and process time as possible at runtime without losing any feature.

## CONTEXT

After the 2026-10-04 merges the window beach-balled with ~150 open pull
requests. `sample` showed the main thread at 100% inside SwiftUI stack layout
with almost no Hyperlite frames. The hang reproduced deterministically by
posting `j`/`k` key events to the `main` build: CPU stayed at 100% after the
keys stopped. Scrolling and hovering alone did not reproduce it.

Orchestration: single-lane, because the hang fix and resource work share the
same view and helper paths and were validated together.

## REQUIREMENTS

- R1: Keyboard navigation, Command-P jumps, scrolling, and hovering never pin
  the main thread.
- R2: Idle CPU returns to zero; hidden windows spend no timer renders.
- R3: Helper calls (refresh, activity poll, cache reads) avoid redundant
  process spawning while staying exact.
- R4: Every existing feature and behavior is preserved.

## ACCEPTED PLAN

1. Replace the nested LazyVStack of project sections with an eager VStack and
   scroll directly to entries.
2. Give the running-chip elapsed label a fixed width and pause chip ticks while
   the window is hidden.
3. Memoize discovery inspections across helper runs, keyed by the files the
   git commands read.
4. Decode scans off the main thread.

## DECISIONS

- Root cause: #129 put project sections in a LazyVStack that was not the
  ScrollView's direct content, and #130 made every `j`/`k` call
  `ScrollViewReader.scrollTo`. Scrolling to an entry inside lazily estimated,
  very uneven section heights (one-line headings to a 65-row project) never
  converged, so layout repeated forever. The eager stack keeps the memoized
  panel model from #129, which was the real CPU win, and makes `scrollTo`
  exact.
- The inspection cache stamps `.git`, the common directory's `config`,
  `packed-refs`, `refs/heads/{main,master,trunk}`, the remote's `HEAD` ref,
  and global and system git config. Any change re-runs git, so remotes,
  renames, and base branches stay exact. The cache is disposable; a missing or
  corrupt file only costs one inspection.
- Chip ticks use a visibility-aware TimelineSchedule instead of removing the
  live elapsed time.

## DISCOVERIES

- Synthetic `CGEvent` key and scroll events reach the app and reproduce
  interaction bugs headlessly, while screen capture and AppleScript keystrokes
  are blocked in this environment.
- Discovery ran four to five git processes per repository on every helper call,
  including the per-minute activity poll: about 400 processes and 8 CPU-seconds
  per call for 102 repositories.

## VALIDATION

- Reproduction: 60 `j`/`k` presses left the `main` build at 100% CPU
  indefinitely; the fixed build returned to 0% within two seconds.
- Long scrolls and hover parking on the fixed build return to 0% CPU.
- Helper: `pull-requests --local` went from 1.43 s wall, 8.2 CPU-seconds cold
  to 0.01 s warm with an unchanged inspection cache.
- Go test: a persisted inspection spawns no git, and a changed remote URL
  re-inspects.
- `make fmt-check vet test-race build macos-test macos-build` passed.

## OUTCOME

- The window no longer hangs; idle CPU is zero; per-call helper cost dropped
  from seconds of CPU to milliseconds.

## REPOSITORY MEMORY

- This spec records the root cause and the inspection-cache contract; code
  comments guard against reintroducing a nested lazy stack.
