---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0014"
  slug: open-pr-conflicts-hide-drafts
  dir: 0014-open-pr-conflicts-hide-drafts
references:
  - id: issue-57
    name: Show merge conflicts and hide drafts in Open PRs
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/57
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pull-requests
    name: Configured Project Pull Requests
    type: specification
    target: docs/specs/0004-open-pull-requests/SPEC.md
    relation: constrains
    read_policy: must
    used_for: read-only pull-request projection and cache behavior
    status: active
  - id: dashboard-list-organization
    name: Dashboard List Organization
    type: specification
    target: docs/specs/0008-dashboard-list-organization/SPEC.md
    relation: informs
    read_policy: must
    used_for: quiet header controls and local presentation filters
    status: active
  - id: reviewed-pull-request-markers
    name: Reviewed Pull Request Markers
    type: specification
    target: docs/specs/0009-reviewed-pull-request-markers/SPEC.md
    relation: informs
    read_policy: must
    used_for: leading review checkbox and header-control density
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: presentation, interaction-state, and component boundaries
    status: active
  - id: backend-architecture
    name: Backend Service Architecture
    type: ruleset
    target: docs/references/rules/backend-service-architecture.md
    relation: constrains
    read_policy: must
    used_for: GitHub gateway mapping without policy in the query builder
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: focused Go mapping and Swift presentation evidence
    status: active
skills: []
---
# Open PR Merge Conflicts And Hide Drafts

## PURPOSE

Let the operator see confirmed merge conflicts in the Open PRs list and hide
draft rows with one quiet header checkbox, without adding GitHub mutation or
another query path.

## CONTEXT

Open PRs is a read-only cached GraphQL projection. Rows already show repository,
number, ready/draft, actionable review-feedback count, title, and age. Header
icons already filter, sort, clear local review marks, and reorder. Drafts stay
in the index because they are open work, but they add noise when the operator
is scanning mergeable ready lanes.

The lightweight query currently omits GitHub `mergeable`. The heavier thread
scanner already treats `CONFLICTING` as a resolve-conflict blocker. This feature
lifts only that confirmed conflict signal onto the compact dashboard row.

The existing filter popover can already restrict State to Ready. The requested
control is a one-click header checkbox, not a replacement for that popover.

## REQUIREMENTS

- R1: Fetch `mergeable` on the existing batched open-pull-request GraphQL query.
  Do not add a per-pull-request request or change refresh cadence.
- R2: Persist `has_merge_conflict` on the cached projection. Treat GitHub
  `CONFLICTING` as true. Treat `MERGEABLE`, `UNKNOWN`, empty, and legacy cache
  without the field as false. Do not treat unknown or missing values as stale.
- R3: Render a compact attention icon after ready/draft and before the
  review-feedback count only when `has_merge_conflict` is true. Keep the column
  aligned when the icon is absent. Availability rows must keep their metadata
  alignment with the widened row.
- R4: Add a quiet Open PRs header checkbox that hides draft rows from the
  visible list. Drafts remain in the cached index. The control lights up when
  hiding drafts and is included in the filtered `n/m` count.
- R5: Hide-drafts is a session presentation toggle on the existing local
  filter, like other Open PRs filters. It does not persist, does not query
  GitHub, and does not change reorder mode, which still shows every loaded row.
- R6: Keep GitHub read-only. Do not change Projects, review markers, quota
  presentation, or the CLI human-readable listing beyond the JSON field the
  dashboard already consumes.
- R7: Preserve macOS 13 compatibility, existing accessibility patterns, and the
  300-line handwritten source/test limit.

Non-goals:

- Filtering or sorting by conflict independently of the new column.
- Persisting hide-drafts across launches.
- Showing unknown mergeable state as a distinct glyph.
- Mutating pull requests, posting reviews, or implying merge permission.

Observable acceptance:

- A conflicting current row shows the conflict icon; a ready non-conflicting
  row and a legacy cached row without the field do not.
- Enabling hide-drafts removes draft rows and keeps ready rows; disabling it
  restores drafts. Reorder mode shows drafts even while the toggle is on.
- Decoding current cache JSON without `has_merge_conflict` succeeds.
- The complete repository validation gate passes.

## ACCEPTED PLAN

1. Add `mergeable` to the lightweight GraphQL node fields and map
   `CONFLICTING` onto `has_merge_conflict` at the GitHub client boundary.
2. Decode the new optional JSON field in Swift with a false default and expose
   it on dashboard rows.
3. Add a reserved conflict column and accessibility text; widen availability
   metadata so cached/unavailable rows stay aligned.
4. Add `hideDrafts` to the existing Open PRs filter and a header checkbox that
   toggles it through the current organization state.
5. Cover GraphQL mapping, JSON compatibility, conflict presentation, and
   hide-drafts composition with focused tests. Update the user guide.
6. Validate with the full code-level and macOS packaging gate. Deliver one
   ready PR from issue 57 without merging.

## DECISIONS

- Topology: `single-lane, because tightly coupled`. The JSON cache contract,
  Swift decode, row layout, and header filter share one interface; splitting
  them would create high overlap. Cursor can launch children, but this change
  needs continuous layout judgment rather than parallel lanes.
- Confirmed conflicts only. GitHub `UNKNOWN` is common while mergeability is
  computed; treating it as stale would refresh-loop, and showing a glyph would
  false-alarm.
- Hide-drafts stays on the existing session filter rather than a persisted
  preference so it matches current Open PRs filter lifetime and does not grow
  `HyperliteDashboardListState` past the line limit.
- Conflict icon uses the existing orange attention token and
  `exclamationmark.triangle.fill`, distinct from the numeric review-feedback
  column.
- No Constitution change. Read-only GitHub projection and local presentation
  filters are already project-wide invariants.
- Accessibility and copied prompts must not treat `has_merge_conflict == false`
  as confirmed mergeable. VoiceOver omits conflict text unless GitHub reported
  `CONFLICTING`; copied observations use `merge conflicts not confirmed`.

## DISCOVERIES

- `internal/prindex/client.go` was already at the 300-line limit, so mapping
  `mergeable` onto the cached projection required a small `client_map.go`
  helper rather than inlining another struct literal.
- Swift rejects assigning a `let` that already has a default value inside the
  custom decoder. The new `hasMergeConflict` field therefore has no stored
  default; tests pass `false` explicitly while JSON decoding still defaults
  missing keys to false.
- Hide-drafts had to be excluded from the filter-popover active glyph and Clear
  action so the header checkbox can stay on while the popover is cleared.
- `kit spec` regenerated `docs/PROJECT_PROGRESS_SUMMARY.md` from feature
  purpose text and dropped historical index content. The delivery restored
  `origin/main` and added only the 0014 row, summary, and changelog bullet.

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build`: PASS. Go
  formatting, vet, unit/race suites, CLI build, native type-check, executable
  Swift model tests, and universal app packaging passed. The only compiler
  warnings are the existing macOS 14 `onChange` deprecations retained for
  macOS 13 compatibility.
- Focused Go `TestGitHubClientMapsMergeConflicts`: PASS for `CONFLICTING`,
  `MERGEABLE`, `UNKNOWN`, and omitted `mergeable`.
- Focused Swift Open PRs controls tests: PASS for legacy cache compatibility,
  confirmed-conflict decoding, hide-drafts filtering and composition, and
  conflict-column layout reservation.
- `codesign --verify --deep --strict build/Hyperlite.app`: PASS. `plutil -lint`
  passed for the packaged Info.plist.
- `lipo -archs` reported `x86_64 arm64` for both `Hyperlite` and
  `hyperlite-cli`.
- `kit check --project` and `kit check --all`: PASS after SPEC placeholders
  were replaced. `kit reconcile --all --dry-run`: no-op.
- Whole-project source-size audit: PASS; `source-file-size audit: complete
  (381 version-control-eligible candidates; 300 eligible handwritten
  source/test files checked; 0 above 300 physical lines)`.
- `git diff --check`: PASS.
- Live dashboard click-through: SKIPPED to avoid quitting the operator's
  running Hyperlite instance. Presentation behavior is covered by executable
  Swift model tests.

## OUTCOME

Open PRs now shows a reserved merge-conflict column after ready/draft. A
confirmed GitHub `CONFLICTING` value renders an orange triangle; other
mergeable states and legacy cache rows stay blank. The lightweight GraphQL
query fetches `mergeable` in the existing batched request and caches
`has_merge_conflict` without changing refresh cadence.

A header checkbox hides draft rows for the current session. Drafts remain in
the cached index, reorder mode still shows every loaded row, and the existing
filter popover State picker is unchanged. Hide-drafts counts toward the `n/m`
title without lighting the popover filter glyph.

## REPOSITORY MEMORY

- Decision: created
- Rationale: confirmed-versus-unknown mergeable handling, hide-drafts as a
  session filter rather than a persisted preference, and the decision not to
  treat unknown mergeable as stale are product rationale that tests cannot
  fully preserve.
- Artifacts: `docs/specs/0014-open-pr-conflicts-hide-drafts/SPEC.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`, `docs/USER_GUIDE.md`,
  `docs/references/testing.md`, and `README.md`. Constitution unchanged.
