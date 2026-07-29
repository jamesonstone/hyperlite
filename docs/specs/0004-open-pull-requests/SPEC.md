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
    used_for: shared scrolling layout and fresh project-lane presentation
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

- R1: Render a visually subdued Open PRs panel immediately below the notepad,
  followed directly by Projects in one shared scrolling content region.
- R2: Include every currently open pull request in each configured GitHub
  repository, including drafts and pull requests from every author.
- R3: Show repository, pull-request number, title, draft or ready state, and
  age; selecting a row opens its GitHub URL. Reserve a wide aligned column for
  repository identity, keep number, state, and age compact, and make the pull
  request title yield horizontal space first. Only unusually long repository
  identities truncate within their reserved column.
- R4: Render cached results immediately at launch, then refresh stale results
  in the background.
- R5: Treat five minutes as the minimum automatic refresh interval. Startup and
  application-foreground events may refresh stale data; the existing explicit
  Refresh action bypasses freshness.
- R6: Fetch configured repositories in bounded GraphQL batches, paginate only
  repositories that exceed one page, and never launch one `gh` process per
  configured repository.
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

Non-goals: CI or review-detail hydration, authored-only filtering, turning open
pull requests into inferred threads or attention moments, continuous timers,
background indexing, pull-request actions, or configuration schema changes.

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
  never removes a checkout; it only stops rendering an unconfirmed subordinate
  lane.
- Pull-request refresh remains serialized behind the heavier evidence refresh
  when both are enabled so one user action does not launch concurrent GitHub
  request bursts. While attention presentation is disabled, native attention
  enrichment does not run.
- Repository identity is the row's primary orientation label. It receives a
  stable wide column so rows remain aligned; pull-request titles retain their
  full accessible value but truncate visually before that identity column.

## ACCEPTANCE CRITERIA

- AC1: The native window shows Open PRs immediately below the notepad and
  Projects directly after the final PR or availability row in the same
  scrolling content region.
- AC2: Draft and ready pull requests from all authors decode and render with
  their repository, number, title, state, age, and URL. Common repository names
  remain readable in a widened aligned column, while long pull-request titles
  truncate before the repository column yields.
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
  accessibility.

## VALIDATION MAP

| Acceptance | Evidence |
| --- | --- |
| AC1-AC2, AC7 | Swift model and presentation tests plus native type-check/build |
| AC3 | Go service and client tests with fake clock and command runner |
| AC4 | Go partial-failure/cache tests and Swift availability decoding tests |
| AC5 | Adapter command assertions and implementation self-review |
| AC6 | Head-branch transport tests and Swift fresh project-lane projection tests |

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

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build` passed.
- `kit check 0003-inferred-attention` and
  `kit check 0004-open-pull-requests` passed. `kit check --project` remains
  blocked by the same six unrelated V3 support-document drift findings already
  present on `main`; none is in this feature's changed paths.
- Focused Go tests cover bounded batching, multi-page retrieval, partial
  GraphQL errors, query-error redaction, five-minute success and failure
  throttling, force refresh, cached fallback, unavailable repositories,
  private atomic storage, corruption preservation, transactional concurrent
  updates, repeated-cursor and page-limit guards, and CLI mode selection.
- Native executable model tests cover schema decoding, recent-first ordering,
  draft and ready labels, cached and unavailable states, URL preservation, and
  the five-minute floor. Row-layout coverage exercises both current and
  availability row presentations, fixes a minimum 180-point repository
  allocation, and proves repository identity has higher horizontal priority
  than the PR title. Project-lane tests prove exact case-sensitive head branch
  filtering, primary-checkout retention, cached suppression, and removal after
  a successful empty refresh. Swift type-checking passed with only the two
  existing macOS 14 `onChange` deprecation warnings in
  `HyperlitePaletteViews.swift`.
- One isolated-cache live validation queried all 16 configured projects in one
  GraphQL batch and returned 18 open pull requests, 0 unavailable projects, 0
  errors, and 0 warnings.
- The universal signed app was built and launched. The native accessibility
  tree and screenshot confirmed that Open PRs begins immediately below the
  notepad and Projects follows its final row in the same scrolling region. The
  single-column Projects list retained every configured checkout, labeled each
  primary branch and subordinate worktree explicitly, and exposed full project,
  branch, and path values to accessibility.
- A second isolated packaged-app inspection at the supported narrow/default
  window width confirmed that common repository identities such as
  `lsmc-bio/lsmc-vivarium` remain fully visible, long identities retain a
  distinguishing repository prefix, and long PR titles truncate to protect
  the aligned repository, number, state, and age columns. Accessibility labels
  retain the complete repository and title.
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

Open PRs and Projects share the native content region. Projects follows the
final PR row as one grouped vertical list in configuration order. Its exact
current head-branch projection controls subordinate worktree visibility:
cached or unavailable evidence cannot retain an active lane, and a successful
refresh that no longer reports a merged or closed PR removes that lane from
Projects without deleting or pruning any checkout. Open PR rows reserve a
190-point aligned repository column and let the title yield horizontal space
first, so project identity remains useful even when a pull-request title is
unusually long.

## REPOSITORY MEMORY

Decision: updated.

Rationale: refresh authority, cache ownership, batching, failure semantics, and
the separation from attention are durable product decisions that code and tests
alone do not fully explain.

Artifacts: `docs/specs/0004-open-pull-requests/SPEC.md`,
`docs/CONSTITUTION.md`, `docs/PROJECT_PROGRESS_SUMMARY.md`, and `README.md`.
