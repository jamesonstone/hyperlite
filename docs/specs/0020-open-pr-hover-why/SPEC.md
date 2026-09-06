---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0020"
  slug: open-pr-hover-why
  dir: 0020-open-pr-hover-why
references:
  - id: issue-72
    name: Make Open PR hover a glanceable what/why and next step
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/72
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-workspace-scanability
    name: Open PR Workspace Scanability
    type: specification
    target: docs/specs/0019-open-pr-workspace-scanability/SPEC.md
    relation: constrains
    read_policy: must
    used_for: in-memory hover card and batched GraphQL glance fields
    status: active
  - id: open-pull-requests
    name: Configured Project Pull Requests
    type: specification
    target: docs/specs/0004-open-pull-requests/SPEC.md
    relation: constrains
    read_policy: must
    used_for: cached-first Open PR projection and batched GraphQL
    status: active
  - id: backend-architecture
    name: Backend Service Architecture
    type: ruleset
    target: docs/references/rules/backend-service-architecture.md
    relation: constrains
    read_policy: must
    used_for: prindex GraphQL gateway field expansion and summary mapping
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: hover presentation of summary and next step
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Go summary tests and Swift hover presentation tests
    status: active
skills: []
---

# Open PR Hover What-And-Why

## PURPOSE

Make Open PR hover a readable glance: what the change is, why it exists, and
the single next step. Prefer design readability over information density.

## CONTEXT

Hover already dumps identity, branch, author, assignees, diffstat, comments,
CI, SHA, and URL. Operators still open GitHub to learn intent, and the card
is too dense to scan for status.

The existing batched query can carry `bodyText` and a few recent commit
headlines without extra round trips. Derivation stays local and
deterministic: no model call, no per-row fetch.

Orchestration: single-lane, because GraphQL mapping and hover presentation
share one summary contract and need continuous judgment about what to omit.

## REQUIREMENTS

- R1: Expand the existing batched Open PR GraphQL nodes with `bodyText` and
  the last three commit `messageHeadline` values. Keep CI state on the newest
  of those commits. Do not add GitHub round trips.
- R2: Map a truncated `summary` onto `model.ProjectPullRequest`. Omit it when
  nothing useful remains. Cache and CLI JSON stay backward compatible.
- R3: Prefer a labeled "Original ask" body paragraph when present. Otherwise
  use the first useful body paragraph. Skip headings, checklists, issue
  trailers, and text that only repeats the PR title.
- R4: If the body yields nothing useful, fall back to recent commit headlines
  that are not merge commits and not duplicates of the title.
- R5: Hover shows compact identity, title, optional summary (wrapped, at most
  three lines), one next step, and at most one supporting status line. Do not
  dump author, labels, assignees, diffstat, comments, SHA, or URL. Hover
  still never fetches.
- R6: Next step prefers merge conflicts, failing CI, unresolved review
  threads, a stale local review mark, draft, pending CI, then waiting on
  review. Approved with no blockers is "ready to merge". Blocking steps use
  the attention color.
- R7: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Generating summaries with a language model.
- Extra GitHub API calls.
- Showing the full PR body, commit list, or every glance field.

Observable acceptance:

- A PR whose body starts with Original ask shows that ask on hover.
- A PR with only a title-matching conventional-commit headline and an empty
  body omits summary rather than repeating the title.
- A PR with merge conflicts shows "fix merge conflicts" as the next step,
  not a list of metadata.
- Hover does not call GitHub.

## ACCEPTED PLAN

1. Add `bodyText` and `commits(last: 3) { messageHeadline, statusCheckRollup }`
   to the existing batched query. Read CI from the newest commit node.
2. Derive `summary` in `prindex` from body then commit headlines. Persist only
   the truncated summary.
3. Replace the hover field dump with identity, title, summary, and one next
   step derived in Swift from already-fetched glance fields.

## DECISIONS

- Prefer Original ask over Implementation summary: hover needs why, not a
  changelog.
- Truncate at 160 runes on a word boundary so the card stays three lines.
- Keep derivation in Go so CLI JSON and the app share one rule.
- Omit SHA, URL, author, and diffstat from hover; the row already identifies
  the PR and the click opens GitHub.

## DISCOVERIES

- GitHub `commits(last: 3)` nodes are oldest-first, so CI must read the last
  node. `last: 1` made `nodes[0]` coincidentally newest.
- Dumping every glance field made hover slower to read than the row itself.
  One next step plus a short why is the scannable contract.
- `kit spec` rejects numeric-prefixed slugs, so this spec was authored
  directly as `0020-open-pr-hover-why`.

## VALIDATION

- `make fmt-check vet test` and `make test-race` cover summary derivation,
  CI-from-newest-of-three, and `bodyText` / `commits(last: 3)` query shape.
- `make macos-test` covers hover summary, conflict next step, omitted dense
  metadata, and summary JSON decoding.
- `make macos-build` produces `build/Hyperlite.app`.
- Interactive hover on a live Open PR list is operator follow-up after the
  packaged app is opened.

## OUTCOME

Open PR hover shows compact identity, title, a truncated what-and-why when
the scan has one, and one next step. Blocking steps use the attention color.
Author, diffstat, SHA, and URL stay off the card. Summary comes from the
existing batched fetch with no extra GitHub round trip.

## REPOSITORY MEMORY

- Decision: not required
- Rationale: Hover layout is feature-local. No new project-wide invariant
  belongs in the Constitution. Operator-facing behavior is in the user guide.
- Artifacts: `docs/specs/0020-open-pr-hover-why/SPEC.md`,
  `docs/USER_GUIDE.md`, `docs/references/testing.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`
