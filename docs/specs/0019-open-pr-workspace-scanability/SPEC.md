---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0019"
  slug: open-pr-workspace-scanability
  dir: 0019-open-pr-workspace-scanability
references:
  - id: issue-68
    name: Improve Open PR scanability with hover, themes, pins, and type size
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/68
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
    used_for: cached-first Open PR projection and batched GraphQL
    status: active
  - id: command-palettes
    name: Performant Command Palettes And Diagnostics
    type: specification
    target: docs/specs/0002-command-palettes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: Command-K overlay, delayed hover, no extra I/O on hover
    status: active
  - id: dashboard-list-organization
    name: Dashboard List Organization
    type: specification
    target: docs/specs/0008-dashboard-list-organization/SPEC.md
    relation: supersedes
    read_policy: must
    used_for: Open PR sort, filter, hide-drafts, and enter/exit reorder chrome
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: appearance state, Open PR organization, hover presentation
    status: active
  - id: backend-architecture
    name: Backend Service Architecture
    type: ruleset
    target: docs/references/rules/backend-service-architecture.md
    relation: constrains
    read_policy: must
    used_for: prindex GraphQL gateway field expansion
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Go query tests and Swift presentation tests
    status: active
skills: []
---

# Open PR Workspace Scanability

## PURPOSE

Make Open PRs readable at a glance: larger type, hover details from the
existing batched GitHub fetch, a pinned section with drag-to-reorder, and
Command-K-only light and dark themes. Quiet the window chrome by moving the
ghost into the title bar as `👻 hyperlite`.

## CONTEXT

Open PR rows render at 10pt JetBrains Mono with only a URL tooltip. The
batched GraphQL query already returns identity, draft, mergeable, review
threads, and updated time; hover cognition needs author, branch, labels,
assignees, diffstat, review decision, review requests, comment count, and CI
without extra round trips.

The Open PR header currently exposes sort, filter, hide-drafts, copy-prompt,
clear-reviewed, and a transactional reorder mode. Those controls are replaced
by a persistent Pinned section plus always-on drag. Per-row reviewed-by-me
marks remain.

The application is a single hardcoded Selenized Dark palette. Theme and font
size must be reachable only from Command-K nested lists, persist locally, and
recolor native chrome in light themes.

The in-app `Hyperlite 👻` brand duplicates the window title. The window title
lookup in the application delegate currently matches `"Hyperlite"` exactly.

Orchestration: single-lane, because theme tokens, palette modes, Open PR
rows, and appearance state share files and need continuous design judgment.
Cursor can spawn children, but predicted overlap is high.

## REQUIREMENTS

- R1: Command-K Font Size is a nested list with 12 pt (default) and 10 pt.
  The choice persists. Body/list type uses the selected size; compact chrome
  stays 10 pt when body is 12 and 8 pt when body is 10. No Settings, menu, or
  header font control.
- R2: Expand the existing batched Open PR GraphQL nodes with glance fields.
  Do not add extra GitHub API round trips. Cache and CLI JSON remain backward
  compatible with omitted fields.
- R3: Hovering an Open PR row opens a delayed, unpinned Hyperlite hover card
  from in-memory scan data. Hover never fetches. Card covers title, repo,
  number, draft/ready, branch, author, labels, assignees, `+/-`/files,
  conflicts, unresolved review threads, review decision, review requests,
  comment count, CI, reviewed-by-me, age, short SHA, and URL.
- R4: Open PRs shows a Pinned section above the remaining rows. Dragging a
  row reorders immediately and persists. Dragging into Pinned pins; dragging
  out unpins. Remove Open PR header sort, filter, hide-drafts, copy-prompt,
  clear-reviewed, and enter/exit reorder chrome. Copy Open PR Merge Prompt
  stays in Command-K. Reviewed-by-me row marks remain.
- R5: Eleven theme families, each with dark and light variants (22 palettes):
  Selenized, GitHub, Gruvbox, Monokai, Tokyo Night, One Dark/Light, Dracula,
  Catppuccin, Nord, pink-accent, and lilac-accent. Default remains Selenized
  Dark. Command-K Theme opens a nested list; the current theme is marked;
  choosing one applies immediately and persists. No other theme UI.
- R6: Light themes set `colorScheme` to light and recolor every Hyperlite-
  painted surface, including notepad AppKit text, palette, settings, and
  hover cards, so contrast remains readable.
- R7: Remove the in-app Hyperlite 👻 title. Window title is `👻 hyperlite`.
  Keep rate-limit and git-maintenance header actions. Window lookup uses the
  new title.
- R8: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Extra GitHub API calls or Beacon-style pinned evidence panels.
- Theme or font controls outside Command-K.
- Changing Dock/bundle display name.
- Removing per-row reviewed-by-me marks.

Observable acceptance:

- Default launch uses 12 pt list type and Selenized Dark.
- Command-K Font Size and Theme nested lists mark the current choice.
- Hovering a current Open PR shows glance fields present in the scan JSON.
- Dragging a row into Pinned and relaunching keeps it pinned in that order.
- Light theme makes canvas, text, and notepad colors light.
- Window title is `👻 hyperlite` and the in-app brand header is absent.

## ACCEPTED PLAN

1. Add `HyperliteAppearance` (theme id + font size) persisted in UserDefaults.
   Map 22 named palettes onto existing semantic tokens. Wrap the window with
   an observing theme modifier that also sets `colorScheme`.
2. Add Command-K nested modes for Theme and Font Size. Escape returns to
   Commands. Selecting a value applies immediately and leaves the nested list
   open with the current item marked.
3. Extend `prindex` GraphQL node fields and map them onto
   `model.ProjectPullRequest` optional JSON. Decode leniently in Swift.
4. Replace the Open PR URL tooltip with a delayed hover card built from the
   row plus glance fields.
5. Replace Open PR organization chrome with pinned/unpinned arrays, always-on
   drag, and section drop targets. Persist both arrays.
6. Set `WindowGroup` title to `👻 hyperlite` and update lifecycle window
   lookup. Remove the in-app brand stack.

## DECISIONS

- Keep Selenized Dark as the default so existing operators are unchanged
  until they pick another theme.
- Font size is one Command-K choice that sets the body/compact pair rather
  than two independent sliders.
- Pinning is local presentation metadata, not GitHub state. Unpinning is the
  restore path.
- Nested palettes stay inside the same overlay; they do not open Settings.

## DISCOVERIES

- `HyperliteApp` cannot live in the Swift test binary because of `@main`.
  Window-title constants therefore live in `HyperliteAppearance.swift`.
- Theme tests must assert `HyperliteThemeCatalog.palette(for:)`, not
  `HyperliteTheme.canvas`, because the latter reads live UserDefaults.
- One Dark and One Light share family name `One` so the catalog remains
  eleven families with twenty-two palettes.
- Open PR sort/filter/hide-drafts APIs remain in `HyperliteDashboardListState`
  for reviewed-by-me and existing tests; they are no longer presented in the
  Open PRs header.

## VALIDATION

- `make fmt-check vet test` and `make test-race` cover Go mapping of glance
  fields from the expanded batched GraphQL nodes.
- `make macos-test` covers Command-K Theme and Font Size nested lists, 22
  palettes, pin/reorder presentation, hover glance lines, and window title.
- `make macos-build` produces `build/Hyperlite.app`.
- Native interactive Command-K, hover, and drag verification is operator
  follow-up after the packaged app is opened.

## OUTCOME

Open PRs default to 12 pt list type and Selenized Dark. Command-K Theme and
Font Size are nested lists that mark the current choice. Hovering a row shows
in-memory glance fields from the same batched fetch. Pinned is a persistent
drag-reorder section; dropping into it pins and dropping out unpins. The
window title is `👻 hyperlite`; the in-app brand header is gone. Light themes
set native `colorScheme` and recolor Hyperlite-painted surfaces.

## REPOSITORY MEMORY

- Decision: updated
- Rationale: Feature rationale lives in this spec; Command-K-only appearance
  and local Open PR pins are project-wide invariants in the Constitution;
  operator-facing behavior is in the user guide.
- Artifacts: `docs/specs/0019-open-pr-workspace-scanability/SPEC.md`,
  `docs/CONSTITUTION.md`, `docs/USER_GUIDE.md`, `docs/references/testing.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`
