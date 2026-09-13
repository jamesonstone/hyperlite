---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0032"
  slug: open-pr-design-pass
  dir: 0032-open-pr-design-pass
references:
  - id: issue-98
    name: "Open PRs design pass: readability, hierarchy, de-emphasize no-action projects"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/98
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-project-sections
    name: Open PR Project Sections
    type: specification
    target: docs/specs/0027-open-pr-project-sections/SPEC.md
    relation: supersedes
    read_policy: must
    used_for: heading color and idle availability rows
    status: active
  - id: open-pr-workflow-activity
    name: Open PR Workflow Activity
    type: specification
    target: docs/specs/0031-open-pr-workflow-activity/SPEC.md
    relation: constrains
    read_policy: must
    used_for: Pulls/Actions buttons, notable workflow chips, hide-idle filter
    status: active
  - id: readable-workspace-layout
    name: Readable Workspace Layout
    type: specification
    target: docs/specs/0025-readable-workspace-layout/SPEC.md
    relation: constrains
    read_policy: must
    used_for: stacked height estimate and title-first rows
    status: active
  - id: lean-native-window
    name: Lean Native Window
    type: specification
    target: docs/specs/0017-lean-native-window/SPEC.md
    relation: constrains
    read_policy: must
    used_for: notes and Open PRs remain the only native surfaces
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Open PR panel presentation
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Swift presentation tests and macos-test
    status: active
skills: []
---

# Open PR Design Pass

## PURPOSE

Make Open PRs scan as a hierarchy: a stronger panel title, bright headings
for projects that have work, and a single dim line for everything else.

## CONTEXT

Feature 0031 gave every configured project a section, a workflow strip, and
Pulls/Actions buttons. Idle projects then rendered a full-strength heading,
a meaningless compact `+N` idle-workflow count, and a separate
`no open pull requests` row — three lines of equal weight. The panel title
used the same heading size as each repository, so nothing read as the top of
the list. Section labels, chips, idle text, and PR rows started on different
left edges.

Hide-idle remains the default. This pass is about the visible list: hierarchy
when projects have open PRs, and a compacted de-emphasized treatment when
the operator shows idle projects.

Orchestration: single-lane, because heading weight, idle collapsing,
alignment, compact chip filtering, and stacked height share one presentation
contract and need continuous design judgment.

## REQUIREMENTS

- R1: The panel title is larger and brighter than repository section headings
  (`HyperliteTypography.title` is body+5 semibold).
- R2: Projects with open PRs use primary-text heading type. Projects with no
  open PRs fold availability into the heading (`no open pull requests`, or
  cached/unavailable copy) and drop to compact muted type. A no-PR project
  with running or failing work uses regular body type in secondary text.
  No separate idle row.
- R3: Compact layout and idle projects show only running or attention
  workflow chips. They do not show a `+N` idle-workflow count.
- R4: Repository names and PR row text share one content column so the list
  is left-aligned. Workflow chips sit on the heading row after the name so
  they do not insert a second line between the heading and its pull requests.
  Drag, pin, and review chrome stay in a leading rail. Pulls/Actions stay
  trailing.
- R5: Keep pinning, drag-reorder, review toggles, GitHub buttons, running
  chips, hide-idle, and refresh overlays.
- R6: Stacked fit-content height counts folded idle headings, not a second
  availability row.
- R7: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Extra GitHub calls or cache changes.
- Grouping Pinned by project.
- Changing hide-idle membership rules.

Observable acceptance:

- `Open PRs` outranks every repository heading.
- An idle project is one dim line when shown; hiding idle still works.
- Vertical Mode does not show `+N` beside a quiet workflow strip.
- Repository names line up with `#number` / title, not with drag handles.

## ACCEPTED PLAN

1. Promote `Open PRs` to a title size in primary text. Move the hide-idle
   control onto that title row so Pinned is only a pin-rail caption.
2. Fold idle copy into the section heading. Brighten headings with open PRs.
   Indent heading text and chips by the row-chrome width.
3. Filter compact and idle strips to running/attention chips and stop
   rendering `+N`.
4. Drop the extra stacked availability-row height and cover the new
   presentation with Swift tests.
5. Build the app and iterate alignment, spacing, and hover until the pane
   scans as title → project → rows.

## DECISIONS

- Promote `Open PRs` to `HyperliteTypography.title` (body+5 semibold) in
  primary text so it outranks repository headings. Keep the count compact
  and muted. Keep Pinned as a muted caption in the content column, not a
  second title.
- Fold idle copy into the heading instead of a second row. Open-PR headings
  stay semibold heading type in primary text. Quiet idle headings use compact
  muted type so they recede. A no-PR project with a running or failing workflow
  uses regular body type in secondary text so a post-merge deploy still
  reads as live.
- Indent repository names and the Pinned caption by the 64 pt row chrome
  width so they share a column with `#number` / title. Put workflow chips on
  the heading row after the name. Drag, pin, and review stay in the leading
  rail. Pulls/Actions stay trailing. Hide the Pinned caption when the pin rail
  is empty so a zero-count label does not compete with projects that have work.
- Compact and idle strips keep only running and attention chips and never
  render `+N`. Wide active projects still list every workflow.
- Move hide-idle onto the title row so Pinned is only a pin-rail label. Keep
  the control muted while idle projects are hidden (the default) and mark it
  active only while showing them.
- Hover identity stays compact. The glance card puts next-step on an
  elevated surface, separated by a hairline, so the action is the scan
  target.

## DISCOVERIES

- The existing GH-98 commit did not apply cleanly onto squash-merged `main`
  (Button-wrapped repository names, hide-idle, and workflow strips). The
  design was re-applied on the post-#100 tree rather than resurrecting the
  stale patch.
- Compact `+N` counted quiet success and idle chips, not only idle workflows.
  Dropping the count is the compact treatment; filtering the chip list is
  what actually removes the noise.
- The stacked fit-content estimate used only the 16 pt section-label height
  and missed each header's top padding (10 for active projects, 2 for idle,
  6 for Pinned). That made the pane shorter than the rendered list.
- Screen capture of the local window was blocked by macOS ScreenCaptureKit
  policy in this environment. Validation is Swift tests plus a local
  `make hyper` launch. A second pass dropped idle headings from semibold
  heading type to compact muted type, enlarged the panel title to body+5,
  and kept the hide-idle control muted in the default hidden state so it
  does not compete with the title.

## VALIDATION

- `make macos-test` passed after the hierarchy, idle-fold, compact-chip,
  stacked-height, idle-type, title-size, inline-chip, and empty-Pinned
  changes.
- `make macos-build` produced `build/Hyperlite.app` and `make hyper` launched
  it. Interactive screenshot verification was SKIPPED (ScreenCaptureKit
  unavailable to the agent).

## OUTCOME

- Native Open PRs now scan as title, then project, then rows. Idle projects
  collapse to one compact muted line. Ready pull-request delivery through
  issue #98.

## REPOSITORY MEMORY

- Feature rationale lives in this spec. USER_GUIDE and testing.md record the
  operator-visible hierarchy. Constitution unchanged: hide-idle membership
  and the notes-plus-Open-PRs native window are the same invariants.
