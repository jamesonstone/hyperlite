---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0044"
  slug: open-pr-layout-and-scroll
  dir: 0044-open-pr-layout-and-scroll
references:
  - id: issue-138
    name: "Open PRs layout: quick facts header, sticky project headers, footer, no quiet-ones list"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/138
    relation: implements
    read_policy: must
    used_for: accepted scope
    status: active
  - id: open-pr-runtime-efficiency
    name: Open PR Runtime Efficiency
    type: specification
    target: docs/specs/0043-open-pr-runtime-efficiency/SPEC.md
    relation: informs
    read_policy: must
    used_for: the nested lazy stack hang this layout must not reintroduce
    status: active
skills: []
---

# Open PR Layout And Scroll

## PURPOSE

Give the pull request list as much readable space as possible, surface
operational facts in the header, pin project headers while scrolling, and make
scrolling smooth.

## CONTEXT

The list had a separate title row, a quiet-ones disclosure, and an empty
header strip left of the window buttons. Scrolling was choppy: a scripted
400-tick scroll down and back cost 8.04 CPU-seconds. Rows also drew below
their frames, so the next project header covered a row's text.

Orchestration: single-lane, because the layout, pinned headers, and scroll
cost share one list structure.

## REQUIREMENTS

- R1: Quick facts left of the window buttons, prioritized to fit.
- R2: Project headers pin while their rows scroll.
- R3: No quiet-ones list; hidden projects stay reachable through the eye.
- R4: Footer with last update and version.
- R5: No main-thread hang under keyboard navigation or Command-P jumps.
- R6: Rows never draw outside their frames.

## ACCEPTED PLAN

1. Make the panel own the pane: top bar (facts, spinner, eye, window
   buttons), list, footer.
2. Render the list as a LazyVStack with pinned section headers that is the
   ScrollView's direct content, rows as lazy children.
3. Move collapse state to one published store shared by list, navigation, and
   jumps.
4. Center-align rows with an explicit height.
5. Cut per-row interactive regions and memoize fonts and the palette.

## DECISIONS

- Pinned headers require a lazy stack. 0043 showed a lazy stack nested below
  the ScrollView's content hangs under `scrollTo`; as the direct content with
  uniform row heights it converges. Verified with the same 60-key `j`/`k`
  sequence that hung before: CPU returns to zero.
- Rows use center alignment and a fixed height derived from the list font.
  First-baseline alignment across plain buttons and a height-less spacer had
  pushed text below the frame.
- The row is one button that opens the pull request; the `GH-<n>` issue number
  is a separate button overlaid on its column, only when present. Profiling
  showed scroll time dominated by SwiftUI hit-testing every interactive region
  per frame, so fewer regions per row directly cut scroll cost. Tooltips that
  duplicated the hover card were dropped; accessibility labels remain.
- Fonts are matched once per size and weight, and the palette once per theme;
  both had been resolved on every access.
- The quiet-ones attention count survives as the `hidden failing` fact.
- The footer version comes from `git describe --tags --always --dirty` and the
  commit stamped into Info.plist by the build script.

## DISCOVERIES

- Synthetic scroll events land wherever the pointer is; measurements are valid
  only while the window is frontmost and the operator is not using the screen.

## VALIDATION

- Scroll cost: 8.04 CPU-seconds before, 3.35 after (-58%) for the same
  scripted scroll; resident memory 213 MB to about 135-220 MB depending on
  realized rows.
- 60 `j`/`k` presses: CPU returns to zero within two seconds.
- `make fmt-check vet test-race build macos-test macos-build` passed.

## OUTCOME

- Facts header, pinned project headers, footer, no quiet-ones list, aligned
  rows, and smoother scrolling.

## REPOSITORY MEMORY

- USER_GUIDE documents the layout; this spec records why pinned headers are
  safe here and the scroll-cost decisions.
