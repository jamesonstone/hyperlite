---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0047"
  slug: open-pr-row-columns
  dir: 0047-open-pr-row-columns
references:
  - id: issue-173
    name: Align Open PR row diffstat and comments into scan columns
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/173
    relation: implements
    read_policy: must
    used_for: accepted scope
    status: active
  - id: open-pr-row-diffstat
    name: Open PR Row Diffstat
    type: specification
    target: docs/specs/0046-open-pr-row-diffstat/SPEC.md
    relation: amends
    read_policy: must
    used_for: glance counts stay informational; columns now reserve empty sides
    status: active
  - id: open-pr-row-attention
    name: Open PR Row Attention
    type: specification
    target: docs/specs/0042-open-pr-row-attention/SPEC.md
    relation: amends
    read_policy: must
    used_for: failed pipelines stay reserved so they do not shift number columns
    status: active
skills: []
---

# Open PR Row Columns

## PURPOSE

Make Open PR trailing metadata scan as columns: added counts, removed counts,
comments, and age each occupy a reserved slot so the eye can travel down one
datapoint at a time.

## CONTEXT

Feature 0046 placed green `+N` and red `-N` immediately left of the comments
icon. Those views used intrinsic width and hid missing sides, so a 26,899-line
diff sat in a different horizontal place than a 953-line diff, and a row
without comments slid its numbers against the age. The list could not be read
as columns.

Glance already has `additions`, `deletions`, and `ci_state`. No extra fetch.

Orchestration: single-lane. Layout widths, comments-column states, and the
user guide share one row contract.

## REQUIREMENTS

- R1: Reserve fixed trailing columns, right to left: age, comments, removed,
  added, then failed pipelines. Title truncates before those columns yield.
- R2: Added counts stay green and right-aligned in the added column. Removed
  counts stay red and right-aligned in the removed column. A zero side leaves
  the cell empty and keeps the width.
- R3: The comments column always shows one glyph: a red speech-bubble count
  when unresolved review threads exist; a cyan cycling icon when `ci_state` is
  `PENDING` or `EXPECTED` and there are no unresolved threads; otherwise a
  green check.
- R4: Failed pipeline names stay in the reserved pipeline column. They clip
  rather than push the number columns.
- R5: Reuse glance fields. Add no GitHub request.
- R6: VoiceOver names the comments-column state. Hover still omits a dumped
  diffstat.
- R7: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Extra GraphQL fields or round trips.
- Hover-card diffstat.
- Compact `k`/`m` abbreviations.
- Animated timers on every row.

Observable acceptance:

- `+26899` and `+953` share one right-aligned column.
- A row with no comments shows a green check in the same column as a
  speech-bubble count.
- A row with pending CI and no unresolved threads shows a cycling icon in
  that comments column.

## ACCEPTED PLAN

1. Add reserved column widths and a comments-column presentation helper.
2. Render the trailing columns on every row, with empty cells keeping width.
3. Cover column widths and the three comments states with Swift tests.
4. Update the user guide.

## DECISIONS

- Two number columns, not one combined `+N -N` blob, so each datapoint lines
  up with the same datapoint on the row above.
- Comments-column empty state is a green check. The cycling icon is only for
  pending or expected CI, and only when there are no unresolved threads.
- Use `arrow.triangle.2.circlepath` for the pending glyph. A `ProgressView`
  or `TimelineView` on every pending row would wake the list for animation.
- Keep failed pipelines in their own reserved column. Putting them in the
  flex title would still be fine for titles, but leaving them intrinsic in
  the trailing cluster would shift every number column.
- Project headings with rows keep primary type on a full-width surface band
  and a hairline. Cyan on that surface fails 4.5:1 in several light palettes.
  A left-only color change would not mark the break when the eye is on the
  trailing columns. Idle headings stay muted and unbanded.

## DISCOVERIES

- Age labels are `now`, `Nm`, `Nh`, or `Nd`. Four characters cover the
  oldest-on-list case.

## VALIDATION

- `make macos-test` passed. New Swift tests cover comments-column states
  (threads, pending, clear), reserved trailing widths, and row spoken text.

## OUTCOME

- Every Open PR row reserves columns for failed pipelines, added counts,
  removed counts, comments, and age. A zero side stays empty. The comments
  column shows a speech-bubble count, a cyan cycling icon for pending CI, or
  a green check.

## REPOSITORY MEMORY

- This spec records the column order and comments-column states.
  `docs/USER_GUIDE.md` describes the visible columns.
  `docs/references/testing.md` names the new presentation tests.
