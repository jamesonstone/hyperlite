---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0018"
  slug: runtime-resource-cut
  dir: 0018-runtime-resource-cut
references:
  - id: issue-66
    name: Cut idle and launch-time Hyperlite resource use
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/66
    relation: implements
    read_policy: must
    used_for: accepted scope and observable acceptance
    status: active
  - id: lean-native-window
    name: Lean Native Window
    type: specification
    target: docs/specs/0017-lean-native-window/SPEC.md
    relation: constrains
    read_policy: must
    used_for: retained notes and Open PRs surface
    status: active
  - id: notepad-daily-notes
    name: Notepad And Daily Notes
    type: specification
    target: docs/specs/0006-notepad-daily-notes/SPEC.md
    relation: constrains
    read_policy: must
    used_for: on-device semantic search remains, embeddings load lazily
    status: active
  - id: frontend-architecture
    name: Frontend Application Architecture
    type: ruleset
    target: docs/references/rules/frontend-application-architecture.md
    relation: constrains
    read_policy: must
    used_for: window lifecycle and palette-owned project list
    status: active
  - id: testing
    name: Testing And Environment Validation
    type: ruleset
    target: docs/references/rules/testing-and-environment-validation.md
    relation: constrains
    read_policy: must
    used_for: Swift exact-search without embedding and semantic path
    status: active
skills: []
---
# Runtime Resource Cut

## PURPOSE

Cut Hyperlite's idle and launch-time CPU, memory, and helper work without
removing notes, Open PRs, or on-device semantic note search.

## CONTEXT

After the lean-window cut, a long-running packaged app sits at ~0% CPU, but
launch still does avoidable work: the global hotkey force-refreshes GitHub,
`HyperliteState` spawns `projects list` before Command-P needs it, note
indexing loads Apple's sentence embedding for every chunk, and the binary
still links unused UserNotifications and sqlite3.

Open PRs still load at launch because that list is on screen. Explicit Refresh
and Force Cache Refresh keep their GitHub authority.

Topology: `single-lane, because tightly coupled`. Window lifecycle, helper
spawn, search indexing, and linked frameworks share one runtime contract.

## REQUIREMENTS

- R1: The global hotkey shows the window. It does not force a GitHub refresh.
  Startup and foreground activation still refresh stale Open PRs. Explicit
  Refresh and Force Cache Refresh are unchanged.
- R2: Launch indexes note filenames, dates, and contents for literal search
  without loading the Natural Language sentence embedding. The embedding and
  chunk vectors load only when a query has no literal match.
- R3: Launch does not spawn `projects list`. Command-P, Remove Project, and
  Settings load the configured-project list when opened. Explicit Refresh
  still reloads it after add/remove.
- R4: The native executable no longer links UserNotifications or sqlite3.
  Carbon and NaturalLanguage remain for the hotkey and lazy embeddings.
- R5: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Removing semantic note search.
- Changing Open PRs GitHub read-only refresh authority for explicit Refresh.
- Splitting or deleting Go CLI command packages.
- Infrastructure or deployment changes.

Observable acceptance:

- Hotkey brings the window forward without starting a force refresh.
- Exact Command-K note search works before any embedding load.
- Semantic Command-K search still retrieves related notes after that load.
- Launch does not run `projects list`.
- `otool -L` on the app binary has no UserNotifications or libsqlite3.

## ACCEPTED PLAN

1. Change the hotkey action to show the window only.
2. Index notes with nil vectors; fill vectors on the semantic search path.
3. Drop `projects list` from `HyperliteState.init`; load it from palettes
   and Settings `onAppear`.
4. Remove unused `-framework UserNotifications` and `-lsqlite3` from the
   Makefile type-check/test compile and `scripts/build-macos-app.sh`.
5. Cover deferred embedding in Swift tests and update constitution, user
   guide, and notepad search timing.

## DECISIONS

- Keep semantic search. Defer the embedding instead of deleting it.
- Treat becoming-active stale Open PR refresh as enough for hotkey show;
  do not special-case a second GitHub path on the hotkey.
- Load the project list whenever Command-P, Remove Project, or Settings
  appear rather than caching launch emptiness, so those surfaces stay current
  without a launch spawn.
- Stop linking leftover Agent Island / Codex frameworks rather than leaving
  them for unused dyld work.

## DISCOVERIES

- `search` previously called `vector(for: query)` even for exact hits, so the
  first Command-K substring search loaded the embedding. Literal ranking must
  finish before any embedding access.
- `replace` copied unchanged indexed notes, so once vectors exist they stay
  until that note's content changes. New or edited notes start with nil
  vectors and fill on the next semantic query.
- Settings does not render the project list, but Add Project and later
  Command-P share `configuredProjects`, so Settings `onAppear` is the
  preload that avoids an empty Remove Project sheet after a settings-only
  session.

## VALIDATION

- `make fmt-check vet test macos-test macos-build` passed. Existing macOS 13
  `onChange` deprecation warnings remain.
- Swift executable tests cover exact Command-K search without embedding calls
  and preserved semantic retrieval after deferred vector fill.
- `otool -L` on both architectures of `build/Hyperlite.app/Contents/MacOS/Hyperlite`
  lists SwiftUI, AppKit, Carbon, and NaturalLanguage; it does not list
  UserNotifications or libsqlite3.
- `git diff --check` passed.
- `kit check --project --all` reported a coherent project contract.
- `kit check --all` passed all 17 feature specifications.
- `kit reconcile --all --dry-run` reported `source-file-size audit: complete`
  with 0 files above 300 lines. Managed-file refreshes were not applied.
- Idle CPU of an already-running packaged app was previously ~0%; this change
  does not replace that process.

## OUTCOME

The global hotkey shows the window without forcing GitHub work. Launch indexes
note literals without loading sentence embeddings, and it does not spawn
`projects list` until Command-P, Remove Project, Settings, or explicit Refresh
needs the list. Semantic Command-K search still fills vectors on first use.
The app binary no longer links UserNotifications or sqlite3.

## REPOSITORY MEMORY

- Decision: created
- Rationale: launch and idle resource policy is product intent that tests
  cannot fully preserve, including what must not run until a surface needs it.
- Artifacts: `docs/specs/0018-runtime-resource-cut/SPEC.md`,
  `docs/CONSTITUTION.md`, `docs/USER_GUIDE.md`, `docs/references/testing.md`,
  `docs/specs/0001-standalone-hyperlite/SPEC.md`,
  `docs/specs/0006-notepad-daily-notes/SPEC.md`
