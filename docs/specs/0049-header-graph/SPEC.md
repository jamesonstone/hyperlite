---
kit_metadata_version: 1
artifact: "spec"
workflow_version: 3
phase: "deliver"
feature:
  id: "0049"
  slug: "header-graph"
  dir: "0049-header-graph"
---
# SPEC

## PURPOSE

Show the open-pull-request summary as a compact animated graph in the header,
so the same counts read as one instrument instead of a flat text row.

## CONTEXT

`HyperliteQuickFacts` already builds the header facts, in priority order, and
omits zero counts. `HyperliteQuickFactsBar` rendered them as text and dropped
lower-priority facts when the window was narrow. The refresh badge, rate-limit
indicator, hide-idle eye, and window buttons sit on that same bar and stay
where they are. The native window is SwiftUI on macOS. This cloud checkout
cannot run the macOS app.

Issue: https://github.com/jamesonstone/hyperlite/issues/179

## REQUIREMENTS

- Replace the text row with one segment per visible fact, colored from the
  active theme palette.
- Size count segments by their counts. Widths ease to the new sizes when a
  refresh changes the data.
- Keep every segment's label and count readable, in the segment when it fits
  and on hover when it does not.
- Keep the header on one line, at about the current height.
- Leave the refresh and rate-limit indicators and the right-side controls
  unchanged.
- Do not drop facts to fit. A narrow window compresses segments.
- Honor Reduce Motion by applying the new widths immediately.

## ACCEPTED PLAN

1. Keep fact selection in `HyperliteQuickFacts`.
2. Add a layout type that turns those facts into segments, widths, captions,
   and palette roles. Test that type without rendering.
3. Replace the text bar with a strip that fills the free space in the header.
   A clear flexible frame owns the width. An overlay reads it. A raw
   `GeometryReader` in the header row would take the row's whole width and
   crush the controls.
4. Draw each segment as a quiet tint, a 2-point meter, and monospaced text in
   the same palette color. Hover brightens the segment and, when the label
   does not fit, floats that label. The existing definition stays on the
   tooltip.
5. Describe the strip in the user guide.

## DECISIONS

- A segmented bar, not a sparkline. These facts are one snapshot of statuses,
  not a series over time.
- Counts share one scale, including projects and deploy gaps, because the
  header is comparing the numbers it already shows.
- `oldest` is an age. Giving it a weight of days would let a 167-day pull
  request dominate the bar, so it is a fixed end cap.
- Tone colors stay red for alerts and orange for attention. Open uses primary
  text. Ready uses green. Updated today and running use cyan, the same accent
  as in-progress work. Other neutral facts use secondary text. Oldest uses
  muted text. Fills stay near the canvas so the text keeps the contrast of
  the old row.
- Segments no longer disappear when the window narrows. The old priority
  cutoff hid real counts. Compression plus hover keeps them.
- The strip does not become a control. It is not a button and it does not
  enter keyboard navigation.

## DISCOVERIES

- The header row's free space has to be measured by a flexible child. Putting
  `GeometryReader` directly in that `HStack` collapses the eye and the window
  buttons.

## VALIDATION

From the GH-179 worktree:

- `make fmt-check vet` passed.
- `make test` failed in `TestInspectCacheReusesUntilGitConfigChanges`
  (`calls=7`). This sandbox sets `GIT_CONFIG_COUNT`, and discovery disables
  its inspect cache for command-scoped git config. That failure is outside
  this change.
- `go test ./...` and `go test -race ./...` with `GIT_CONFIG_COUNT` unset
  passed. `make build` passed.
- `make macos-test` was not run. This machine has no Swift, SwiftUI, AppKit,
  or Carbon. That check is what compiles the strip and runs
  `HyperliteHeaderGraphTests`.
- The native window was not launched. A layout preview using the Monokai
  palette and the same width rules was rendered in a browser. It is not a
  capture of Hyperlite.app.

## OUTCOME

The header's free space is a segmented strip. Each visible quick fact is a
segment. Count segments ease when their widths change. Oldest stays a fixed
end cap. Hover shows a label that does not fit and the existing definition.
The refresh badge, rate-limit indicator, eye, and window buttons are unchanged.

## REPOSITORY MEMORY

- This spec records the graph, the oldest end cap, and why facts are no
  longer dropped to fit.
- `docs/USER_GUIDE.md` describes the strip.
- `docs/references/testing.md` names the layout tests.
- `docs/specs/0044-open-pr-layout-and-scroll/SPEC.md` stays historical. Its
  quick-fact header is the behavior this strip replaces.
