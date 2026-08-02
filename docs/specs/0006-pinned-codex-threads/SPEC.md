---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0006"
  slug: pinned-codex-threads
  dir: 0006-pinned-codex-threads
references:
  - id: issue-25
    name: Show pinned Codex threads in Hyperlite
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/25
    relation: implements
    read_policy: must
    used_for: product scope and observable acceptance
    status: active
  - id: codex-app-server
    name: Codex App Server
    type: external-reference
    target: https://learn.chatgpt.com/docs/app-server.md
    relation: informs
    read_policy: evidence
    used_for: future documented pinned-thread source boundary
    status: active
skills: []
---

# Pinned Codex Threads

## PURPOSE

Hyperlite should show the operator's pinned Codex Desktop threads as a compact,
neutral header projection without turning them into inferred project threads,
attention events, or mutable Hyperlite state.

## CONTEXT

Codex Desktop currently records pin membership in the required
`pinned-thread-ids` array in `.codex-global-state.json`, while `state_5.sqlite`
contains useful thread metadata. In the installed environment, the global state
contains pins while the database's `threads.is_pinned` values are all false and
one pinned ID has no database row. Treating SQLite as membership authority would
therefore report a plausible but incorrect zero.

Codex's documented App Server exposes pinned-thread APIs, but its storage model
is evolving independently of Desktop's current global state. Hyperlite needs a
narrow source adapter so a future documented implementation can replace the
private Desktop reader only after compatibility evidence proves both sources
agree.

## REQUIREMENTS

- Treat only a valid `pinned-thread-ids` array as authoritative membership.
  Preserve first-seen order and deduplicate IDs without consulting metadata.
- Distinguish current, partial, and unavailable snapshots. Missing, unreadable,
  oversized, malformed, missing-key, null, or wrong-shaped membership is
  unavailable, never an empty current snapshot.
- Enrich authoritative IDs from read-only SQLite using only ID, name, title,
  working directory, and update time. A missing row or title keeps the ID in the
  count and makes metadata partial; unrelated rows never add membership.
- Keep Codex access read-only and bounded. Do not log, cache, render, or expose
  unrelated global-state values, transcript content, previews, or raw errors.
- Load at startup, refresh after foreground activation only when a source
  signature changes, and force refresh through the existing Refresh actions.
  Do not add polling, timers, file watchers, or background indexing.
- Render a compact header indicator and bounded popover with explicit loading,
  zero, partial, and unavailable presentation while preserving the 480-point
  minimum width and shared typography.
- If current membership becomes unavailable, remove its count and rows. Retain
  only the prior successful observation time for diagnostic text.

Non-goals: opening, pinning, unpinning, renaming, or otherwise mutating Codex
threads; reading transcripts; changing Hyperlite's Go or JSON interfaces;
bundling a database library; or activating an App Server adapter in this work.

Observable acceptance: the displayed deduplicated count matches valid Desktop
global state; incomplete SQLite metadata retains that count with fallback IDs;
invalid membership displays unavailable; foreground and forced refreshes cannot
be overwritten by older work; and a read-only live check observes no Hyperlite
writes to Codex state.

## ACCEPTED PLAN

1. Add internal pinned-thread models, a source protocol, and a bounded Desktop
   adapter for required JSON membership plus optional read-only SQLite metadata.
2. Add an independent observable state owner with source signatures,
   cancellation, generation protection, startup load, activation refresh, and
   forced refresh integration.
3. Add a neutral header indicator immediately before Refresh and a bounded,
   non-navigating popover for rows, empty state, availability, and timestamps.
4. Link system SQLite into the native app and executable Swift tests; add
   deterministic adapter, state, presentation, and SQLite fixture coverage.
5. Validate against fixtures and live Codex state, run the complete repository
   gate, and curate README, progress, Constitution, and this spec to delivered
   behavior.

## DECISIONS

- Desktop global JSON is the v1 membership authority because current live
  evidence disproves SQLite membership. SQLite is enrichment only.
- Use a dedicated observable state instead of enlarging `HyperliteState`; the
  existing refresh methods coordinate it so every established trigger remains
  consistent.
- Track the JSON file, SQLite database, and SQLite WAL because current metadata
  updates can live in WAL while the database file's modification time remains
  unchanged.
- Bound global state at 16 MiB and the pin list at 10,000 non-empty opaque IDs.
  Bounds fail closed instead of guessing or silently truncating membership.
- An absent SQLite database, missing row, or row without a usable name/title is
  partial when pins exist. Missing optional directory metadata alone does not
  reduce membership availability.
- Retain no cached count or rows after authoritative failure. A last-available
  timestamp may explain the outage without representing stale membership as
  current.
- A source that changes across both bounded read attempts publishes unavailable
  without retaining a signature, so the next activation retries. Stable
  unavailable input retains its signature and remains changed-source-only.

## DISCOVERIES

- The installed database uses WAL journaling; its WAL modification time moves
  independently from the main database file.
- System SQLite imports and links for both macOS 13 arm64 and x86_64 targets, so
  no package or bundled library is required.
- A live pin transition changed the authoritative projection from 12 to 11 and
  back to 12 through existing refresh triggers. The current task was restored
  to its original pinned state after validation.
- Hyperlite's explicit refresh left the global-state JSON and main SQLite file
  byte-for-byte unchanged. The WAL continued to move while Codex Desktop was
  active, which confirms why WAL belongs in the change signature but prevents
  treating its concurrent checksum as Hyperlite-specific write evidence.

## VALIDATION

- `make macos-test`
- Live Desktop state shape validation with strict `jq`; 12 unique pins were
  authoritative and one lacked usable SQLite metadata.
- Real application inspection at the normal layout and an approximately
  540-point-wide window; the compact indicator, bounded scrolling popover,
  accessibility labels, partial state, and disabled refresh state remained
  usable.
- Live unpin, explicit refresh, and re-pin exercise: the count changed 12 to 11
  to 12, and the current task's original pinned state was verified afterward.
- Source checksum comparison around explicit refresh; global JSON and main
  SQLite remained unchanged while Codex Desktop independently advanced WAL.
- `make fmt-check vet test test-race build macos-test macos-build`; all tests
  and builds pass, with only the existing macOS 14 `onChange` deprecations.
- Deterministic torn-read coverage verifies that repeated source mutation fails
  closed and that the next ordinary activation can recover without a forced
  refresh.
- `kit check pinned-codex-threads` and
  `kit check dashboard-project-management`; both pass.
- `kit check --project`; the 11 blocking findings exactly match `origin/main`
  and remain out-of-scope instruction-document and existing source-size debt.
- `codesign --verify --deep --strict build/Hyperlite.app`; `lipo -archs` confirms
  both native executables contain `x86_64` and `arm64`, and `otool -L` confirms
  the native executable links the system `libsqlite3`.

## OUTCOME

Hyperlite now presents pinned Codex Desktop tasks immediately before Refresh in
the native header. A dedicated state owner and narrow source protocol keep the
private Desktop reader isolated, retain authoritative membership through
metadata gaps, discard all rows after membership failure, and protect newer
refresh results from older work. No Go or JSON interface changed, and the UI is
informational and non-navigating.

## REPOSITORY MEMORY

- Decision: created
- Rationale: source authority, fail-closed behavior, rejected SQLite membership,
  refresh consistency, and the future adapter boundary are material rationale
  not recoverable from UI code and tests alone. The validated separation of
  this projection from project evidence is also a durable project invariant.
- Artifacts: `docs/specs/0006-pinned-codex-threads/SPEC.md`, `README.md`,
  `docs/PROJECT_PROGRESS_SUMMARY.md`, `docs/CONSTITUTION.md`
