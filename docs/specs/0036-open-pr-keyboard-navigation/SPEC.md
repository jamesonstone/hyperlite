---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0036"
  slug: open-pr-keyboard-navigation
  dir: 0036-open-pr-keyboard-navigation
references:
  - id: issue-108
    name: "Open PRs: hide every no-PR project, enlarge the quiet-ones launcher, add keyboard navigation"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/108
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: open-pr-watch-stage
    name: Open PR Watch Stage
    type: specification
    target: docs/specs/0033-open-pr-watch-stage/SPEC.md
    relation: supersedes
    read_policy: must
    used_for: hide-idle membership and the watching-the-quiet-ones list
    status: active
  - id: open-pr-design-pass
    name: Open PR Design Pass
    type: specification
    target: docs/specs/0032-open-pr-design-pass/SPEC.md
    relation: supersedes
    read_policy: must
    used_for: hide-idle keeps active-workflow projects visible
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: Open PR panel presentation and focus controller boundaries
    status: active
  - id: source-file-size
    name: Source File Size
    type: ruleset
    target: docs/references/rules/source-file-size.md
    relation: constrains
    read_policy: must
    used_for: keep handwritten source and test files at or under 300 lines
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Swift presentation tests and macos-test/macos-build
    status: active
skills: []
---

# Open PR Keyboard Navigation

## PURPOSE

Make the Open PRs pane read as "projects with open pull requests" and let the
operator move through it without the mouse: hide every project without an open
pull request into an enlarged `watching the quiet ones` launcher, add
`j`/`k`/arrow selection with a visible focus highlight, and add `Command+1` /
`Command+2` to focus the Open PRs and Notes panes.

## CONTEXT

After 0032/0033 the hide-idle eye kept a no-PR project visible whenever it had
a running or failing workflow or a cached main/deploy pipeline failure, so a
post-merge deploy would not disappear. In practice this surfaces unrelated
projects (for example `r2` with a failed `Dependabot Updates` run, or
`labcore-ui` with running `Deploy Web`/`CodeQL`) in a list the operator reads
as "what has open PRs". The `watching the quiet ones` disclosure is small,
collapsed each launch, and mouse-only, and nothing in the pane is keyboard
navigable.

Orchestration: single-lane, because the hide-idle membership change, the
enlarged launcher, and the keyboard/focus model share one Open PRs
presentation and selection contract and need continuous design judgment. This
matches 0033, which was single-lane for the same pane.

## REQUIREMENTS

- R1: When the hide-idle eye is on, a project is hidden iff it has no open
  pull-request rows, independent of workflow or pipeline state. Pinned rows and
  projects with open PRs stay in the main list. Showing all projects (eye off)
  still lists every project inline.
- R2: Hidden projects keep their workflow chips and main/deploy pipeline-alert
  badges inside `watching the quiet ones`, so a failure is one expand away, not
  lost. The list caption reports the hidden count and, when any hidden project
  has a failing pipeline or failing workflow, an attention count.
- R3: The `watching the quiet ones` list persists its expanded state across
  launches so it can be used as a project launcher. Its rows open each
  project's repository on GitHub, exactly as an inline idle heading does.
- R4: In the Open PRs pane, `j` / `Down` select the next item and `k` / `Up`
  the previous, across pinned rows, visible project headings, visible
  pull-request rows, the quiet-ones toggle, and expanded hidden headings.
  `Return` opens the selected item (pull request or repository) or toggles the
  quiet-ones list. The selected item shows a clear highlight while the pane is
  focused.
- R5: `Command+1` reveals and focuses the Open PRs pane (leaving Notes Only and
  resigning the notes editor so `j`/`k` navigate rather than type).
  `Command+2` focuses the active Notes editor. `Command+R`, `Command+K`, and
  `Command+P` are unchanged.
- R6: Typing in the Notes editor is never intercepted: navigation keys only act
  when the Notes editor is not first responder and no palette is open.
- R7: Keep handwritten source and test files at or under 300 lines. No new
  GitHub fetch. Stacked (non-compact) layout still gives leftover height to
  notes.

Non-goals:

- Re-adding an always-visible no-PR project to the main list.
- Changing splitter behavior, Notes Only, or the command/project palettes.
- A second GitHub fetch for workflow or project data.

Observable acceptance:

- `r2` and `labcore-ui` leave the main list and appear under `watching the
  quiet ones`; the caption shows the hidden count and any attention count.
- The quiet-ones list stays expanded after a relaunch once opened.
- `j`/`k` and the arrow keys move a visible highlight; `Return` opens the
  selection; `Command+1`/`Command+2` move focus between the panes.

## ACCEPTED PLAN

1. Redefine `HyperliteOpenPRProjectFilter.isIdle` to `section.rows.isEmpty`.
   Keep `hasNotableActivity` for ordering hidden projects (attention first) and
   for the caption attention count.
2. Persist the `watching the quiet ones` expansion in `@AppStorage`; add the
   attention count to `HyperliteHiddenProjectListPresentation`.
3. Add a pure `HyperliteWorkspaceNavigation` model: ordered nav-item ids from
   the rendered sections, selection movement, and key-command classification.
4. Add a `HyperliteWorkspaceFocus` controller (`ObservableObject`, shared) that
   holds the focused pane, the selection id, and the current nav items with
   their actions, and performs focus/move/activate.
5. Install a window-scoped `HyperliteWorkspaceKeyCapture` local key monitor
   that defers to the palette and to the Notes editor's first responder, and
   wire `Command+1`/`Command+2` through the Navigate command menu.
6. Highlight the selected nav item with a reusable modifier and mark the
   focused pane, threading the selection id through the panel.
7. Cover the filter change, caption, nav ordering, selection math, and key
   classification with Swift model tests.

## DECISIONS

- Supersede the 0032/0033 hide-idle membership rule. The main Open PRs list now
  means "projects with open pull requests". Keeping a no-PR project visible for
  workflow activity conflicted with that reading and surfaced unrelated repos.
  The failure signal is preserved because hidden headings still render their
  chips and pipeline-alert badges and the caption reports an attention count,
  and the enlarged, persistent, keyboard-navigable launcher makes them quick to
  reach.
- Navigation keys are routed by a local `NSEvent` monitor (the proven pattern
  from the command palette) rather than SwiftUI `.onKeyPress`, because the pane
  is a custom stacked layout, and the monitor can defer to the Notes editor's
  first responder so typing is never intercepted.
- `Command+1` resigns the editor first responder via the key window so the same
  physical `j`/`k` keys navigate instead of typing; the pure decision is "is the
  Notes editor first responder", not a mode flag, so a mouse click into Notes
  still types normally.

## DISCOVERIES

- `r2`'s `Dependabot Updates` reads as a failed-workflow chip (red dot, orange
  text), so under the old rule its failing run kept a no-PR project in the main
  list. The new rule hides it and the caption's attention count surfaces the
  failure instead.
- `make macos-test` type-checks against the host SDK (macOS 26), so it accepts
  `onChange(of:initial:)`; `make macos-build` targets macOS 13, where that
  overload does not exist. The pane publishes navigation items with the
  macOS-13 one-parameter `onChange` plus an `onAppear`, matching the existing
  palette pattern.
- Selecting the first item inside `setItems` covered a fresh launch in a focus
  ring and a highlighted row no one chose. Gating focus chrome behind a
  `focusVisible` flag that only the keyboard turns on keeps launch quiet while
  still making focus obvious once the operator engages.
- A local `NSEvent` monitor can decide navigation purely from the live first
  responder, so a click into Notes types normally without any pane-mode
  bookkeeping; ⌘1 only needs to resign that first responder.

## VALIDATION

- `make macos-test` passed: full-app type-check plus the executable model
  tests, including the new navigation model (key classification, selection
  movement, reconciliation), the reversed hide-idle membership, the quiet-ones
  attention count, and the updated caption.
- `make macos-build` produced a universal, ad-hoc-signed `build/Hyperlite.app`
  against the macOS 13 deployment target.
- `go vet ./...` passed; no Go sources changed.
- Interactive keyboard behavior (⌘1/⌘2 focus, `j`/`k`/arrow selection, Return
  activation, and the focus ring) is verified by build and the pure navigation
  model tests; live GUI capture is SKIPPED (ScreenCaptureKit is unavailable in
  this environment).

## OUTCOME

- The Open PRs main list now shows only projects with open pull requests; every
  other project — including `r2` and `labcore-ui` — moves into an enlarged,
  persistent `watching the quiet ones` launcher that keeps their chips and
  pipeline-alert badges and reports an attention count. `j`/`k` and the arrow
  keys move a highlighted selection, Return opens the selection or toggles the
  launcher, and ⌘1/⌘2 focus the Open PRs and Notes panes with a clear focus
  ring. Ready pull-request delivery through issue #108.

## REPOSITORY MEMORY

- Feature rationale, including the superseded hide-idle membership rule, lives
  in this spec. USER_GUIDE records the operator-visible hide-idle change, the
  enlarged quiet-ones launcher, and the new keyboard shortcuts. testing.md
  records the new navigation-model tests.
