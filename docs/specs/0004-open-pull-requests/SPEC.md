---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: 0004
  slug: open-pull-requests
  dir: 0004-open-pull-requests
references:
  - id: issue-9
    name: Add configured project pull request panel
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/9
    relation: implements
    read_policy: must
    used_for: product scope and acceptance criteria
    status: active
  - id: issue-11
    name: Focus native workspace on pull requests and notes
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/11
    relation: implements
    read_policy: must
    used_for: layout and project-lane follow-up scope
    status: active
  - id: issue-13
    name: Prioritize project names in Open PR rows
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/13
    relation: implements
    read_policy: must
    used_for: repository-column layout priority
    status: active
  - id: issue-15
    name: Organize active project branches and worktrees
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/15
    relation: implements
    read_policy: must
    used_for: bottom-pinned activity layout and fresh project-lane presentation
    status: active
  - id: issue-17
    name: Improve dashboard layout and project commands
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/17
    relation: supersedes
    read_policy: evidence
    used_for: equal-third layout and absolute freshness follow-up
    status: active
  - id: issue-21
    name: Show unresolved review feedback in Open PRs
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/21
    relation: implements
    read_policy: must
    used_for: actionable review-feedback count and row presentation
    status: active
  - id: issue-23
    name: Show GitHub rate limit in the app header
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/23
    relation: implements
    read_policy: must
    used_for: caller quota observation and compact header presentation
    status: active
---

# Configured Project Pull Requests

## PURPOSE

Hyperlite keeps one quiet, current index of every open pull request across the
configured projects so the operator can see active review lanes without
opening each repository or turning pull-request presence into an attention
event.

## CONTEXT

The current thread scanner retrieves rich GitHub evidence for inferred
coordination, but that evidence is intentionally author-scoped by default and
is expensive: it hydrates issues, pull-request details, checks, and review
threads. Reusing that path for an all-author pull-request panel would either
omit valid pull requests or run the heavy evidence scan every time the compact
index needs a freshness update.

The configured-project map already provides the stable local project order and
GitHub repository identities. The new projection needs a separate bounded
GitHub adapter and cache so it can refresh frequently without increasing the
thread scanner cadence or starting continuous background work.

## REQUIREMENTS

- R1: Render Open PRs followed directly by Projects as one visually subdued
  list region pinned to the bottom of the window below the notepad.
- R2: Include every currently open pull request in each configured GitHub
  repository, including drafts and pull requests from every author.
- R3: Show repository, pull-request number, title, draft or ready state, and
  actionable review-feedback count, and age; selecting a row opens its GitHub
  URL. Reserve a wide aligned column for repository identity, keep number,
  state, feedback, and age compact, and make the pull request title yield
  horizontal space first. Only unusually long repository identities truncate
  within their reserved column.
- R4: Render cached results immediately at launch, then refresh stale results
  in the background.
- R5: Treat five minutes as the minimum automatic refresh interval. Startup and
  application-foreground events may refresh stale data; the existing explicit
  Refresh action bypasses freshness.
- R6: Fetch configured repositories in bounded GraphQL batches, paginate only
  repositories or review-thread connections that exceed one page, and never
  launch one `gh` process per configured repository or pull request in the
  normal path.
- R7: Cache this projection separately from inferred-thread state so concurrent
  refreshes cannot overwrite either state owner.
- R8: A successful empty response is visibly distinct from an unavailable
  repository. On query or repository-resolution failure, retain usable cached
  rows and label them as cached; otherwise show a subdued unavailable state.
- R9: Preserve configuration order for project availability and use
  deterministic recent-first ordering for pull-request rows.
- R10: Keep configured repositories and GitHub read-only. Do not add polling,
  notifications, repository mutation, or pull-request mutation.
- R11: Include each pull request's head branch in the lightweight projection.
  Use that exact case-sensitive branch to show only matching registered
  worktrees in Projects when that project's pull-request status is current.
  Cached or unavailable pull-request data must not present a secondary
  worktree as active. After a successful refresh observes a PR as merged or
  closed, remove its worktree row without deleting or pruning the checkout.
- R12: Render Projects as one vertical column in stable configuration order.
  Group each configured primary branch and its current subordinate worktrees
  under one project identity, showing the branch and abbreviated local path.
  Exclude detached subordinate worktrees even if their retained metadata has a
  branch matching a current open pull request.
- R13: Give unused vertical space to the plain-text notepad. As Open PRs or
  Projects grow, compress the notepad to a small usable editor viewport and
  rely on its native scrollbar for longer notes. If the combined lists still
  exceed the remaining window after that compression, bound and scroll the
  list region rather than clipping content or overflowing the window.
- R14: Define actionable review feedback as GitHub pull-request review threads
  whose `isResolved` and `isOutdated` values are both false. Do not count issue
  comments, review summaries, resolved threads, or outdated threads.
- R15: Render a confirmed zero quietly, emphasize a nonzero actionable count,
  and represent unavailable or legacy cached feedback data distinctly from
  zero. Preserve the complete feedback meaning in accessibility labels.
- R16: If review-thread pagination or decoding fails, do not cache or present a
  partial count as current. Preserve the last usable repository snapshot under
  the existing cached-fallback policy.
- R17: Include GitHub's GraphQL `rateLimit` metadata in every existing bounded
  pull-request query. Do not add a separate quota request, polling loop, timer,
  or `gh` process to the normal refresh path.
- R18: Retain only a complete caller quota observation containing `limit`,
  `used`, `remaining`, `resetAt`, `cost`, and `nodeCount`. A malformed or
  missing quota object must not replace the last complete cached observation
  or invalidate otherwise usable pull-request results.
- R19: Render a compact stacked `used` over `limit` indicator in the native
  header immediately before Refresh and Settings. Keep healthy capacity quiet,
  use warning and critical colors only when remaining capacity crosses bounded
  percentage thresholds, and expose an explicit unknown state before any
  complete observation exists.
- R20: The indicator hover and accessibility text must identify the GraphQL
  resource and include used, limit, remaining, local reset time, last-query
  cost and node count, and observation time when available.
- R21: Present quota details in a Hyperlite-themed popover with app typography
  and comfortable grouped spacing. Hover opens the popover transiently after a
  bounded delay; clicking the indicator opens it immediately and pins it until
  a second click or native dismissal. This interaction must not introduce a
  timer-driven refresh, animation loop, or broader application state.

Non-goals: CI or full review-detail hydration, authored-only filtering, turning
open pull requests into inferred threads or attention moments, continuous
timers, background indexing, pull-request actions, or configuration schema
changes. The rate indicator is informational; it does not predict future cost,
change refresh authority, or mutate GitHub.

## ACCEPTED PLAN

1. Add a small project pull-request model, GraphQL batch client, and independent
   atomic cache in Go.
2. Add a `pull-requests` JSON command with local-cache, stale-refresh, and
   force-refresh modes.
3. Add native decoding, presentation sorting, refresh orchestration, and a
   subdued clickable panel above Projects.
4. Cover GraphQL batching and pagination, five-minute cache behavior,
   partial-failure fallback, schema decoding, ordering, labels, and URLs.
5. Run the complete Go and native macOS validation gates and curate repository
   memory to the delivered behavior.
6. Let Open PRs consume the flexible native content area and project registered
   worktrees through exact open-PR head branches, independent of hidden
   inferred-attention presentation.
7. Widen the aligned repository column for current and availability rows, and
   give the pull-request title lower horizontal layout priority.
8. Put Open PRs and Projects in one scrolling content stack, render Projects
   as one grouped column, and require current PR evidence for secondary
   worktree visibility.
9. Size the combined list region to its content up to the available height,
   pin it below an expanding notepad, and preserve independent scroll
   containment for both surfaces when either must compress.
10. Include the first bounded review-thread page with each pull request, count
    only unresolved non-outdated threads, and batch only the uncommon overflow
    pages. Carry an optional count through cache, JSON, and native presentation
    so legacy cached rows remain explicitly unknown.
11. Add the top-level GraphQL `rateLimit` selection to the existing repository
    and review-thread queries, keep the most recent complete response from the
    scan, and cache that observation independently of per-repository success.
12. Decode the optional quota observation natively and render a small stacked
    header indicator with deterministic warning thresholds, complete hover
    metadata, and one accessibility element.
13. Replace the system help tooltip with a feature-local styled popover. Reuse
    the established delayed hover behavior, model click pinning as transient
    view state, and verify both activation paths in tests and the packaged app.

## DECISIONS

- The pull-request index is a separate informational projection, not inferred
  coordination state or human attention.
- Event-driven startup and application-foreground refreshes honor a five-minute
  cache floor. Explicit refresh is the only force path; Hyperlite does not add
  a timer.
- The lightweight GraphQL adapter requests only list fields and batches
  repositories, while the existing thread scanner retains ownership of rich
  issue, check, and review evidence.
- Cache ownership is separate from thread state to avoid lost updates between
  independently running helper commands.
- The native Projects map treats only current open-PR branches as worktree
  visibility authority. Cached or unavailable PR data can retain its rows in
  Open PRs, but cannot claim a secondary local worktree is active. The map
  also requires that a secondary worktree remains attached; it never removes a
  checkout, only stops rendering an unconfirmed subordinate lane.
- Pull-request refresh remains serialized behind the heavier evidence refresh
  when both are enabled so one user action does not launch concurrent GitHub
  request bursts. While attention presentation is disabled, native attention
  enrichment does not run.
- Repository identity is the row's primary orientation label. It receives a
  stable wide column so rows remain aligned; pull-request titles retain their
  full accessible value but truncate visually before that identity column.
- Vertical whitespace belongs to the notepad, not the activity lists. The
  combined Open PRs and Projects region keeps its intrinsic height and bottom
  edge until it reaches the notepad's minimum usable viewport; beyond that
  point the notepad and lists retain independent scroll containment.
- The feedback indicator counts actionable conversations, not comments: one
  unresolved, non-outdated GitHub review thread contributes one regardless of
  how many comments it contains. The first review-thread page rides with the
  existing repository batch; only overflow connections require additional
  bounded batched queries.
- The feedback count is optional at the model boundary. Missing data from a
  legacy cache is unknown rather than zero, while every successful fresh query
  supplies an exact count. Any incomplete review-thread traversal fails the
  repository refresh and retains its prior usable snapshot.
- GitHub quota metadata belongs to the lightweight pull-request projection
  because that adapter owns every GraphQL request shown by this surface. Each
  query returns `rateLimit` alongside its existing data, so quota visibility
  adds no request or process. The last complete response in a scan is the most
  current caller observation and may update even when one repository result is
  unavailable.
- `used / limit` is the stable compact summary; `remaining` stays explicit in
  hover and accessibility text. Remaining capacity at or below 20 percent is
  a warning and at or below 10 percent is critical. The display does not
  schedule refreshes or infer exhaustion from age.
- The quota detail surface is secondary context rather than a new window or
  workflow. Hover should remain lightweight and self-closing, while click
  intentionally pins the same popover for reading. The popover uses
  `HyperliteTypography` and existing palette tokens instead of native tooltip
  styling or a separate visual system.

## ACCEPTANCE CRITERIA

- AC1: The native window pins the combined Open PRs and Projects region to the
  bottom, keeps Projects directly after the final PR or availability row, and
  gives all remaining vertical space to the notepad.
- AC2: Draft and ready pull requests from all authors decode and render with
  their repository, number, title, state, actionable review-feedback count,
  age, and URL. Common repository names remain readable in a widened aligned
  column, while long pull-request titles truncate before the repository column
  yields.
- AC3: A cache younger than five minutes causes no GitHub process; stale or
  missing repositories are queried in batches; explicit refresh queries every
  resolved repository.
- AC4: Partial query failure preserves cached rows with a cached state, while a
  project with neither a usable GitHub identity nor cache is unavailable.
- AC5: No configured-project or GitHub mutation occurs.
- AC6: Exact registered worktree branches remain visible only while current
  project evidence reports a corresponding open PR; cached, unavailable,
  merged, or closed lanes disappear without deleting local data.
- AC7: Projects render as one grouped vertical column in configuration order,
  with project, branch, and abbreviated path available visually and through
  accessibility. Detached subordinate worktrees remain hidden even when their
  retained branch matches a current open pull request.
- AC8: Larger PR/project sets shrink the notepad to a usable minimum with its
  native scrollbar; list overflow remains reachable through a separate bounded
  scrollbar at constrained window heights.
- AC9: A successful fresh query counts only unresolved, non-outdated review
  threads across every bounded page. Zero, nonzero, and unavailable feedback
  states are visually and accessibly distinct, and selecting the row continues
  to open the pull request URL.
- AC10: Every existing GraphQL request selects the complete GitHub rate-limit
  fields without launching an additional request. The last complete quota
  response is cached and projected in JSON; malformed or absent metadata leaves
  the prior complete observation intact without failing repository data.
- AC11: The header renders a compact stacked used/limit indicator immediately
  before Refresh and Settings. Healthy, warning, critical, and unknown states
  are visually distinct without competing with primary controls, and hover plus
  accessibility expose the full available quota metadata and local timestamps.
- AC12: Hovering the indicator opens a comfortably spaced, Hyperlite-themed
  quota popover in JetBrainsMono Nerd Font. Clicking opens the same popover
  immediately and keeps it visible until a second click or native dismissal;
  keyboard and accessibility users can identify and activate the indicator.

## VALIDATION MAP

| Acceptance | Evidence |
| --- | --- |
| AC1-AC2, AC7-AC9 | Swift sizing/presentation tests plus native type-check/build and packaged-app inspection |
| AC3, AC9 | Go service and client tests with fake clock and command runner |
| AC4, AC9 | Go partial-failure/cache tests and Swift availability decoding tests |
| AC5 | Adapter command assertions and implementation self-review |
| AC6 | Head-branch transport tests and Swift fresh project-lane projection tests |
| AC10 | Go query, client, service, cache compatibility, and partial-response tests |
| AC11 | Swift decoding and presentation tests plus packaged-app hover/accessibility inspection |
| AC12 | Swift interaction-state tests plus packaged-app hover, click, visual, and accessibility inspection |

## DISCOVERIES

- A rate-safe freshness boundary needs the last attempted GitHub check as well
  as the last successful observation. Otherwise a rate-limit or network failure
  can make every foreground activation retry immediately.
- The independent cache must retain the last error with a successful snapshot.
  This lets a later local-only launch distinguish cached rows from a successful
  empty repository without another GitHub call.
- The configured 16-project set fits in one bounded GraphQL batch. Pagination
  remains repository-specific and runs only when a repository reports another
  page.
- Pagination needs both a repeated-cursor guard and a hard page ceiling. A
  malformed or changing GitHub connection must fail into cached state instead
  of consuming an unbounded request budget.
- Returning a cache value loaded before a separate locked mutation can discard
  another process's update from the rendered projection even when persistence
  is correct. The cache transaction returns the exact timestamped snapshot it
  wrote under the lock.
- A 78-point repository column exposes mostly the organization prefix for
  configured repositories and makes otherwise distinct projects look
  identical. A 190-point aligned column fits common repository identities at
  the supported narrow window width while leaving the title as the flexible,
  first-truncated field.
- Retaining cached PR rows is useful for the Open PRs index, but using those
  cached head branches to label local worktrees active can preserve a merged or
  otherwise stale lane. Project-lane visibility therefore has a stricter
  freshness boundary than PR-row availability.
- A fixed notepad height leaves unused space below short activity lists, while
  a permanently full-height list scroll region leaves the same space inside
  the wrong surface. Content-sized lists with a bounded overflow height let
  the notepad own the flexible space without making dense activity unreachable.
- Review feedback is resolved at the thread level, so one unresolved,
  non-outdated thread is the actionable unit regardless of its comment count.
  The first 100 review threads can ride with the normal batched PR query; only
  overflow connections need separate bounded batched continuation queries.
- An optional count preserves additive compatibility with the prior cache and
  JSON schema. A current legacy row triggers one hydration attempt immediately,
  while a failed attempt remains subject to the five-minute failure floor.
- GitHub's live GraphQL schema provides exactly `limit`, `used`, `remaining`,
  `resetAt`, `cost`, and `nodeCount` on `RateLimit`; it does not provide a
  resource-name field. The presentation identifies GraphQL from the adapter
  boundary and otherwise exposes every returned field.
- The existing top-level cache can add an optional quota observation without a
  version migration. Legacy cache files decode with no observation, and an
  incomplete response leaves the prior complete value unchanged.

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build` passed.
- `kit check 0004-open-pull-requests` passed. `kit check --project` remains
  blocked by the same six unrelated V3 support-document drift findings already
  reproduced on untouched `main`; none is in this feature's changed paths.
- Focused Go tests cover bounded batching, multi-page retrieval, partial
  GraphQL errors, query-error redaction, five-minute success and failure
  throttling, force refresh, cached fallback, unavailable repositories,
  private atomic storage, corruption preservation, transactional concurrent
  updates, repeated-cursor and page-limit guards, actionable review-thread
  filtering, batched review pagination, scoped failure recovery, legacy-cache
  hydration, and CLI mode selection.
- Native executable model tests cover schema decoding, recent-first ordering,
  draft and ready labels, cached and unavailable states, URL preservation, and
  the five-minute floor. Feedback coverage distinguishes nonzero, zero, and
  unavailable states, singular/plural accessibility labels, and immediate
  legacy hydration without bypassing the failed-refresh floor. Row-layout
  coverage exercises both current and availability presentations, reserves an
  aligned feedback column, and proves repository identity has higher horizontal
  priority than the PR title. Project-lane and workspace-sizing coverage remain
  passing. Swift type-checking passed with only the three existing macOS 14
  `onChange` deprecation warnings in `HyperlitePaletteViews.swift`.
- Focused quota coverage proves every bounded repository or review continuation
  query selects all six GitHub fields, the final complete response wins,
  malformed metadata cannot replace it, repository failures do not suppress a
  valid observation, legacy caches remain compatible, and cached observations
  survive later missing metadata. Native coverage proves decoding, unknown,
  healthy, 20-percent warning, 10-percent critical, complete hover metadata,
  and accessibility text.
- Popover interaction coverage proves delayed hover opening, safe transfer from
  trigger to detail surface, idle dismissal, immediate click pinning,
  second-click dismissal, and native-dismissal cleanup. Packaged-app inspection
  confirmed the indicator is an accessible button; click rendered the styled
  334-point popover with all quota fields, and a second click closed it. The
  detail surface uses only `HyperliteTypography` and established palette tokens
  with 16-point outer padding and grouped metric, time, and query sections.
- An isolated live scan returned 16 configured projects, 10 open pull requests,
  zero errors, zero warnings, and one complete rate-limit observation from the
  existing batch. The observed sample was 1788 used of 5000, 3212 remaining,
  cost 16, and node count 161600.
- The signed packaged app first exposed an explicit unknown quota while its
  cached-first refresh ran, then rendered `1812` over `5000` immediately before
  Refresh. The accessibility tree exposed 3188 remaining, the local reset and
  observation times, cost 16, and node count 161600; the healthy indicator
  remained visually quieter than the adjacent controls.
- One isolated-cache live validation queried all 16 configured projects in one
  GraphQL batch and returned 7 open pull requests, 0 unavailable projects, 0
  errors, and 0 warnings. It reported exactly 2 actionable threads for
  `lsmc-bio/labcore#138`, matching a direct live schema query that found 17
  total review threads.
- The universal signed app was built and launched. The native accessibility
  tree and screenshot confirmed that a 60-line notepad owns the flexible space
  above the bottom-pinned activity region and exposes its native scrollbar.
  Open PRs begins immediately below the notepad and Projects follows its final
  row in the same region. At a constrained window height, the notepad retained
  a small usable editor viewport and the activity region exposed a separate
  scrollbar; scrolling reached the final project and worktree rows. The
  single-column Projects list retained every configured checkout, labeled each
  primary branch and subordinate worktree explicitly, and exposed full project,
  branch, and path values to accessibility.
- A second isolated packaged-app inspection at the supported narrow/default
  window width confirmed that common repository identities such as
  `lsmc-bio/lsmc-vivarium` remain fully visible, long identities retain a
  distinguishing repository prefix, and long PR titles truncate to protect
  the aligned repository, number, state, and age columns. Accessibility labels
  retain the complete repository and title.
- The issue-21 signed packaged app loaded seven legacy cached rows with explicit
  unknown feedback, hydrated them once, and then rendered orange `2` and `12`
  counts alongside quiet zero dashes. Its accessibility tree exposed complete
  phrases such as `2 unresolved review threads`, and every PR button retained
  its exact GitHub URL as the row action.
- An isolated issue-15 preview first loaded seven-minute-old cached PR evidence
  and correctly showed no subordinate worktrees. Its one bounded refresh
  returned 15 current PRs and added exactly seven matching active worktrees,
  while preserving all 16 configured primary branches. Projects remained
  directly after Open PRs in one grouped column.

## OUTCOME

Hyperlite now renders a separate informational Open PRs index for every
configured project. It loads a private cache first, refreshes stale repositories
in bounded GraphQL batches after the local project scan completes,
throttles successful and failed automatic checks for five minutes, and lets the
existing Refresh action force a current snapshot. Partial failures retain and
label cached rows; missing repository identity or missing cache remains visibly
unavailable. Repeated pagination cursors and excessive pages fail safely into
that cache boundary. Open pull requests do not change thread liveness,
lifecycle, or attention.

Each Open PR row now includes an exact actionable feedback count immediately
after ready/draft. The count includes only unresolved, non-outdated GitHub
review threads; resolved threads, outdated threads, issue comments, and review
summaries do not contribute. The first thread page stays in the existing
repository batch, overflow pages are fetched in bounded batches, and an
incomplete traversal retains the last complete cached snapshot. Confirmed zero
is quiet, nonzero feedback is orange, legacy unavailable data is explicit, and
the entire row continues to open GitHub for resolution.

The header now includes a compact GitHub GraphQL quota fraction showing calls
used out of the caller's limit. Every existing bounded query selects the complete
rate-limit object, so the display adds no request or process. The last complete
observation is cached independently of repository success; missing or malformed
metadata cannot erase it. A Hyperlite-themed, JetBrainsMono Nerd Font popover
exposes remaining capacity, local reset and observation times, query cost, and
node count with grouped spacing. Hover opens it transiently, while click pins
the same detail surface for reading. Healthy capacity stays subdued, with
warning and critical color reserved for 20 and 10 percent remaining
respectively.

The notepad owns otherwise unused vertical space and scrolls natively for long
notes. Open PRs and Projects remain bottom-pinned as one content-sized activity
region; if they outgrow the window after the notepad reaches its usable
minimum, that region scrolls independently. Projects follows the final PR row
as one grouped vertical list in configuration order. Its exact current
head-branch projection controls subordinate worktree visibility: cached or
unavailable evidence cannot retain an active lane, detached worktrees are
excluded even if their retained branch still matches, and a successful refresh
that no longer reports a merged or closed PR removes that lane from Projects
without deleting or pruning any checkout. Open PR rows reserve a 190-point
aligned repository column and let the title yield horizontal space first, so
project identity remains useful even when a pull-request title is unusually
long.

Issue #17 supersedes the combined bottom activity region with equal-height,
independently scrollable Notes, Open PRs, and Projects sections. It also
replaces relative Open PR freshness text with a local `yyyy-MM-dd HH:mm`
timestamp. The cache, five-minute automatic refresh floor, PR row projection,
and active-lane rules remain unchanged.

## REPOSITORY MEMORY

Decision: updated.

Rationale: refresh authority, cache ownership, batching, failure semantics, and
the separation from attention are durable product decisions that code and tests
alone do not fully explain.

Artifacts: `docs/specs/0004-open-pull-requests/SPEC.md`,
`docs/CONSTITUTION.md`, `docs/PROJECT_PROGRESS_SUMMARY.md`, and `README.md`.
