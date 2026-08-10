---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: 0009
  slug: reviewed-pull-request-markers
  dir: 0009-reviewed-pull-request-markers
references:
  - id: issue-39
    name: Add reviewed pull request markers
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/39
    relation: implements
    read_policy: must
    used_for: product scope and acceptance criteria
    status: active
  - id: open-pull-requests
    name: Configured Project Pull Requests
    type: specification
    target: docs/specs/0004-open-pull-requests/SPEC.md
    relation: informs
    read_policy: must
    used_for: read-only pull-request projection and cache behavior
    status: active
  - id: dashboard-list-organization
    name: Dashboard List Organization
    type: specification
    target: docs/specs/0008-dashboard-list-organization/SPEC.md
    relation: informs
    read_policy: must
    used_for: local presentation-state and list-control ownership
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: interaction, durable local state, and component boundaries
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: focused, complete, and packaged-app evidence
    status: active
---

# Reviewed Pull Request Markers

## PURPOSE

Hyperlite should let the operator privately mark an open pull request as
reviewed for its current code revision, retain that visual organization across
launches, and clear the temporary review set after a merge-order train without
publishing or implying GitHub approval.

## CONTEXT

Open PRs is a read-only GitHub projection with locally persisted sort, custom
order, and collapse preferences. A plain checkbox keyed only by pull-request
identity would become misleading after new commits, while a GitHub comment
would be noisy, difficult to clear, and ambiguous beside GitHub review state.

The lightweight pull-request query already batches configured repositories and
retrieves each head branch. GitHub's `headRefOid` can ride with that same query
without another request. App-local presentation state can then bind a review
mark to the exact observed head commit while keeping GitHub untouched.

## REQUIREMENTS

- R1: Add an accessible leading `Reviewed by me` checkbox immediately before
  the repository name in every Open PR row. Checking it must not open the pull
  request; the remainder of the row retains existing GitHub navigation.
- R2: Persist each mark locally by stable project/pull-request identity with
  the reviewed head commit and mark time. Create or replace a mark only from a
  current row with a nonempty head commit. Never write the mark into scan
  cache, project configuration, a repository, or GitHub.
- R3: Keep reviewed rows in their current order and subtly mute their content.
  When current GitHub evidence reports a different nonempty head commit, make
  the prior mark visibly stale, restore normal row emphasis, and allow one
  action to review the new head.
- R4: Preserve marks while repository data is cached or unavailable. Prune a
  marker for a closed or merged pull request only when a successful current
  repository result authoritatively omits that pull request. Cached rows may
  clear an existing mark but cannot create or replace one.
- R5: Show the reviewed count in the Open PRs header and provide one bulk action
  that clears all reviewed and stale markers, independent of the active filter.
- R6: Extend the existing Open PR filter with All, Unreviewed, Reviewed, and
  Stale local review states. Filtering remains transient and performs no
  refresh or external work.
- R7: Add `headRefOid` to the existing bounded GraphQL query, cache projection,
  CLI JSON, and native model without adding a query, process, timer, or polling
  path.
- R8: Distinguish the local operator mark from draft/ready state, unresolved
  review feedback, checks, branch protection, mergeability, and merge
  authorization in visible help and accessibility text.

Non-goals: GitHub comments, labels, reviews, merge actions, agent-readable
workflow state, automatic merge-order creation, changing PR order when marked,
or treating a review mark as proof that a pull request is safe to merge.

## ACCEPTED PLAN

1. Carry `headRefOid` through the existing Go pull-request projection and add
   focused query, decode, cache, and CLI model coverage.
2. Add a small revision-aware marker model to the existing dashboard
   organization state and persist records through app-local preferences.
3. Reconcile stored records against each scan, invalidating only on current
   head changes and pruning only from authoritative current repository results.
4. Split ordinary row navigation from the leading checkbox, render reviewed
   and stale states, add the header count/bulk clear action, and extend the
   existing filter popover.
5. Cover state transitions, persistence, pruning, filtering, accessibility
   descriptions, and unchanged navigation with focused native tests.
6. Update operator documentation, run the complete local validation gate, and
   inspect the signed universal packaged app and representative interaction.

## DECISIONS

- The feature is named `Reviewed by me`, not `ready`, because it is private
  presentation metadata and cannot establish merge readiness.
- Head commit identity, not `updatedAt`, invalidates a mark. Comments and other
  metadata can change `updatedAt` without changing reviewed code.
- A stale mark is retained as useful context until rechecked or bulk-cleared;
  it is not counted as currently reviewed.
- Cached or unavailable data may display the last known mark but cannot expire
  or prune it. Cached data may clear an existing human-selected mark but cannot
  create or replace one. Current repository evidence is the only creation,
  replacement, and invalidation authority.
- Bulk clear applies to every stored review marker so an active filter cannot
  leave hidden train state behind.
- The local marker remains human-facing. A later merge agent must receive an
  explicit PR list and independently verify exact heads, feedback, checks,
  conflicts, protections, and merge completion.

## DISCOVERIES

- The lightweight projection already owned the head branch but not the head
  commit; the richer inferred-thread model could not be reused without crossing
  the feature's independent cache and refresh boundary.
- The existing Open PR row was one navigation button, so the review checkbox
  required separate sibling controls to avoid nested interactive elements.
- Existing app-local dashboard preferences provide the correct persistence
  boundary; review marks do not need a new file store or scan-cache owner.
- A concurrently running older app can rewrite the shared pull-request cache
  without the additive head-commit field. Treating that incomplete projection
  as stale makes the current helper hydrate exact heads immediately instead of
  leaving checkboxes disabled until the ordinary freshness floor expires.
- Legacy schema-version-1 native payloads may omit the additive head-commit
  field, so native decoding defaults that field to empty and lets the existing
  staleness path request authoritative hydration.

## VALIDATION

- Focused Go projection and CLI tests passed with `go test ./internal/prindex
  ./internal/cli`, including bounded-query selection, missing-head rejection,
  cache round trips, and legacy-cache hydration.
- Native marker, list, state, persistence, filter, accessibility, and existing
  interaction tests passed with `make macos-test`.
- Review-repair coverage confirms cached rows cannot create or replace marks,
  cached reviewed rows remain clearable, and schema-version-1 payloads without
  `head_ref_oid` decode and trigger current-data hydration.
- The complete repository gate passed with `make fmt-check vet test test-race
  build macos-test macos-build`; only the three pre-existing macOS 14 palette
  deprecation warnings remained.
- `kit check --all` and `git diff --check` passed after repository-memory
  curation. `kit check --project` still reports the repository's pre-existing
  Kit instruction-sync and source-size debt; this feature does not expand the
  set of over-limit Swift test files.
- The packaged universal app passed strict deep code-signature verification;
  both the app and bundled helper contain `x86_64` and `arm64` slices.
- Packaged-app interaction verified that the checkbox does not navigate,
  reviewed rows remain ordered and muted, the local review filter reduces the
  list, bulk clear removes hidden marks, and a mark survives quit and relaunch
  before being cleared.
- Follow-up packaged-app inspection verified that each checkbox leads its row
  immediately before the repository name and precedes PR navigation in the
  accessibility order.

## OUTCOME

- Open PRs now offers a private `Reviewed by me` marker bound to each observed
  pull request head commit, with reviewed, stale, and unreviewed presentation.
- Review marks persist in app preferences, survive non-authoritative cached or
  unavailable observations, and are pruned only by successful current
  repository results.
- The Open PRs header reports the current reviewed count and clears all stored
  marks in one action; the existing filter popover can show all, unreviewed,
  reviewed, or stale rows.
- Hyperlite makes no GitHub comment, label, review, or merge mutation. The
  marker remains a human organization aid rather than agent-readable evidence
  or merge authorization.

## REPOSITORY MEMORY

- Created this living feature specification for the material local-state,
  exact-head, invalidation-authority, and non-goal decisions.
- Updated `docs/CONSTITUTION.md` with the demonstrated project-wide boundary
  between private review presentation metadata and GitHub/merge authority.
- Updated `docs/USER_GUIDE.md` and `docs/PROJECT_PROGRESS_SUMMARY.md` with the
  delivered operator behavior and feature index entry.
