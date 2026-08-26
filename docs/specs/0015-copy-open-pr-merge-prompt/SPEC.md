---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0015"
  slug: copy-open-pr-merge-prompt
  dir: 0015-copy-open-pr-merge-prompt
references:
  - id: issue-59
    name: Copy a merge-ready prompt for visible Open PRs
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/59
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
  - id: command-palettes
    name: Performant Command Palettes And Diagnostics
    type: specification
    target: docs/specs/0002-command-palettes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: Command-K action surface without GitHub mutation
    status: active
  - id: open-pr-conflicts-hide-drafts
    name: Open PR Merge Conflicts And Hide Drafts
    type: specification
    target: docs/specs/0014-open-pr-conflicts-hide-drafts/SPEC.md
    relation: informs
    read_policy: must
    used_for: visible-row filters including hide-drafts
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: prompt builder, clipboard adapter, and control composition
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: focused Swift prompt and palette evidence
    status: active
skills: []
---
# Copy Open PR Merge Prompt

## PURPOSE

Let the operator copy a durable coding-agent prompt plus the currently visible
Open PRs list, so they can paste it into an agent that uses `gh` to make each
listed pull request merge-ready. Hyperlite stays a read-only clipboard source.

## CONTEXT

Open PRs is a cached informational projection. Rows already carry identity,
URL, draft/ready, confirmed merge conflicts, and unresolved review-thread
counts. Hide-drafts, the filter popover, sort, and reorder change which rows
are on screen. Hyperlite does not observe whether a branch is behind the
repository default branch and must not call `gh` or mutate GitHub from this
control.

The operator asked for both the Open PRs header and Command-K, currently
visible rows, clipboard output with copy confirmation, and a durable prompt
rather than a one-off sentence.

## REQUIREMENTS

- R1: Add a quiet Open PRs header control and a Command-K action that copy the
  same prompt for the same currently visible rows.
- R2: Visible rows follow the on-screen list: hide-drafts, filters, and sort
  apply. Reorder mode copies every loaded row currently shown, including drafts.
- R3: Copy writes the durable instruction plus one observation line per visible
  pull request (repository, number, URL when present, draft/ready, confirmed
  merge conflict or `merge conflicts not confirmed`, unresolved review-thread
  hint) to the clipboard. Confirm a
  successful copy on both surfaces. Do not open a file, note, or GitHub URL.
- R4: Disable or no-op the control when no rows are visible. An empty list must
  not clear or replace the clipboard.
- R5: Keep GitHub read-only. Do not refresh, fetch extra fields, merge, comment,
  label, or otherwise mutate pull requests. Tell the receiving agent to verify
  live GitHub state with `gh`, including behind-default-branch, and not to merge
  unless a later operator request says so.
- R6: Preserve macOS 13 compatibility, existing accessibility patterns, and the
  300-line handwritten source/test limit. Confirmation is a bounded one-shot
  reset, not a refresh loop.

Non-goals:

- Hyperlite calling `gh` or opening listed pull requests.
- Persisting the prompt, copied state, or a generated file.
- Observing behind-default-branch locally.
- Changing hide-drafts, conflict icons, or refresh cadence.

Observable acceptance:

- Header and Command-K copy the same text for the current visible Open PRs.
- Hide-drafts and other filters exclude hidden rows from the copied list.
- A successful copy confirms; an empty visible list does not copy.
- The durable instruction tells a coding agent to use `gh` and not to merge
  unless later asked.

## ACCEPTED PLAN

1. Add a pure prompt builder over visible `HyperlitePullRequestRow` values and
   focused tests for instruction text, row observations, and empty lists.
2. Share displayed-row selection between the Open PRs panel and Command-K so
   both surfaces copy the on-screen list.
3. Add a quiet header copy control and a Command-K action. Successful copies
   write the pasteboard and show a two-second confirmation; empty lists no-op.
4. Keep the Command-K palette open after copy so its command title can confirm.
   The header control shows the same copied state.
5. Update the user guide and land the work on PR 58 with issue 59 traceability.

## DECISIONS

- Topology: `single-lane, because tightly coupled`. The prompt builder, visible
  row selection, header control, palette action, and clipboard confirmation
  share one interface; splitting them would create high overlap.
- Durable prompt text is owned by `HyperliteOpenPRMergePrompt.instructions`,
  not by a one-off operator sentence. Later wording edits should stay in that
  one constant.
- Copy uses the currently visible rows, including reorder-mode drafts, so the
  pasted list matches what the operator sees.
- Confirmation is a two-second one-shot SwiftUI task reset after a successful
  pasteboard write. It is not persisted and is not a GitHub refresh signal.
- Command-K does not dismiss on this action so the copied command remains
  visible. Other commands keep the existing dismiss-then-dispatch behavior.
- Copied conflict observations follow the Open PRs column: confirmed
  `CONFLICTING` is `merge conflicts`; `has_merge_conflict == false` is
  `merge conflicts not confirmed` rather than a claimed absence.

## DISCOVERIES

- `kit spec` regenerated `docs/PROJECT_PROGRESS_SUMMARY.md` from feature
  purpose text and dropped historical index content. Delivery restored the
  pre-command copy and added only the 0015 row, summary, and changelog bullet.
- `HyperliteInteractionModels.swift` was already at the line limit, so
  `commandEntries` moved into `HyperliteInteractionEntries.swift` with the new
  copy command rather than growing the models file.
- `HyperlitePaletteViews.swift` needed room for the visible-count and copied
  flags; palette chrome strings moved into `HyperlitePalettePresentation.swift`.
- Command-K dismisses before dispatch for every other action. This copy action
  returns without dismissing so the command title can confirm the pasteboard
  write. The header uses the same copied flag.
- An empty visible list must not call `NSPasteboard.clearContents()`, or a
  previous copy would be destroyed.

## VALIDATION

- `make fmt-check vet test test-race build macos-test macos-build`: PASS. Go
  formatting, vet, unit/race suites, CLI build, native type-check, executable
  Swift model tests, and universal app packaging passed. The only compiler
  warnings are the existing macOS 14 `onChange` deprecations retained for
  macOS 13 compatibility.
- Focused Swift `HyperliteOpenPRMergePromptTests`: PASS for durable
  instructions, row observations, empty-list text, hide-drafts and reorder
  visible-row selection, and Command-K copy labels.
- `codesign --verify --deep --strict build/Hyperlite.app`: PASS. `plutil -lint`
  passed for the packaged Info.plist.
- `lipo -archs` reported `x86_64 arm64` for both `Hyperlite` and
  `hyperlite-cli`.
- `kit check --project` and `kit check --all`: PASS. `kit reconcile --all
  --dry-run`: no-op; `source-file-size audit: complete (384
  version-control-eligible candidates; 302 eligible handwritten source/test
  files checked; 0 above 300 physical lines)`.
- `git diff --check`: PASS.
- Live dashboard click-through: SKIPPED to avoid quitting the operator's
  running Hyperlite instance. Prompt text, visible-row selection, and Command-K
  labels are covered by executable Swift model tests. Clipboard write and the
  two-second copied confirmation remain unobserved in the live window.

## OUTCOME

Open PRs now has a quiet header copy control, and Command-K has Copy Open PR
Merge Prompt. Both copy the same durable merge-ready instruction plus one
observation line for each currently visible Open PR. Hide-drafts, filters, and
sort apply; reorder mode copies the on-screen list including drafts.

A successful pasteboard write confirms for two seconds on the header icon and
the Command-K command, which stays open. An empty visible list disables the
header control and leaves Command-K as a no-op that does not change the
clipboard. Hyperlite does not call `gh` or mutate GitHub.

## REPOSITORY MEMORY

- Decision: created
- Rationale: the durable prompt contract, visible-row copy semantics, clipboard
  confirmation without a refresh loop, and the decision that Hyperlite must not
  call `gh` are product rationale that tests cannot fully preserve.
- Artifacts: `docs/specs/0015-copy-open-pr-merge-prompt/SPEC.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`, `docs/USER_GUIDE.md`, and
  `docs/references/testing.md`. Constitution unchanged.
