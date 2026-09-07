---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0024"
  slug: open-pr-hover-assignee
  dir: 0024-open-pr-hover-assignee
references:
  - id: issue-79
    name: Show Open PR hover assignee
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/79
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-hover-why
    name: Open PR Hover What-And-Why
    type: specification
    target: docs/specs/0020-open-pr-hover-why/SPEC.md
    relation: constrains
    read_policy: must
    used_for: compact hover identity, summary, and next-step contract
    status: active
  - id: open-pr-workspace-scanability
    name: Open PR Workspace Scanability
    type: specification
    target: docs/specs/0019-open-pr-workspace-scanability/SPEC.md
    relation: constrains
    read_policy: must
    used_for: in-memory hover card and batched GraphQL glance fields
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: hover presentation of already-decoded assignees
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Swift hover presentation tests
    status: active
skills: []
---

# Open PR Hover Assignee

## PURPOSE

Show who is assigned to an Open PR on the delayed hover card so the operator
can see ownership without opening GitHub.

## CONTEXT

Assignees are already fetched on the batched Open PR GraphQL nodes, mapped
into scan JSON, and decoded onto `HyperlitePullRequestGlance.assignees`.
Feature `0020-open-pr-hover-why` omitted them from the card to keep the
glance scannable. The operator now needs that one ownership line back
without restoring the dense metadata dump.

Orchestration: single-lane, because hover snapshot and card rendering share
one presentation contract and the data is already in memory.

## REQUIREMENTS

- R1: Hover shows GitHub assignee logins from the in-memory glance fields.
  Multiple assignees join with commas. Hover still never fetches.
- R2: A pull request with no assignees shows `unassigned`.
- R3: Keep compact identity, title, optional summary, one next step, and at
  most one supporting CI line. Do not dump author, labels, branch, diffstat,
  comments, SHA, or URL.
- R4: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Changing GraphQL, Go mapping, or cache shape.
- Showing avatars or substituting author for assignee.
- Restoring the dense glance field dump.

Observable acceptance:

- An assigned Open PR hover names those logins.
- An unassigned Open PR hover says `unassigned`.
- Author, branch, diffstat, SHA, and URL stay off the card.
- Hover does not call GitHub.

## ACCEPTED PLAN

1. Derive one assignee line in `HyperlitePullRequestHoverPresentation` from
   `glance.assignees`.
2. Render it on the hover card between title and summary.
3. Cover assigned, multiple, unassigned, and JSON decode in Swift tests.
4. Update the user guide and testing reference to mention assignee on hover.

## DECISIONS

- Put assignee on its own compact secondary line instead of the meta row so
  `ready · 6m` stays stable and multiple logins can wrap.
- Show `unassigned` rather than omitting the line; missing ownership is the
  useful signal.
- Supersede `0020` R5 only for assignees. Other omitted glance fields stay
  off the card.

## DISCOVERIES

- not required

## VALIDATION

- `make fmt-check vet test` and `make test-race` pass; Go mapping is unchanged.
- `make macos-test` covers assigned, multiple, unassigned, JSON decode, and
  omitted dense metadata.
- `make macos-build` produces `build/Hyperlite.app`.
- Interactive hover on a live Open PR list is operator follow-up after the
  packaged app is opened.

## OUTCOME

Open PR hover shows compact identity, title, assigned logins or `unassigned`,
a truncated what-and-why when the scan has one, and one next step. Assignees
come from the existing batched fetch with no extra GitHub round trip.

## REPOSITORY MEMORY

- Decision: created
- Rationale: Hover ownership is a product choice that supersedes the 0020
  assignee omission; code and tests cannot preserve that history.
- Artifacts: `docs/specs/0024-open-pr-hover-assignee/SPEC.md`,
  `docs/specs/0020-open-pr-hover-why/SPEC.md`, `docs/USER_GUIDE.md`,
  `docs/references/testing.md`, `docs/PROJECT_PROGRESS_SUMMARY.md`
