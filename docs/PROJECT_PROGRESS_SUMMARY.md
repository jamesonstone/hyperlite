# PROJECT PROGRESS SUMMARY

## FEATURE PROGRESS TABLE

| ID | FEATURE | PATH | PHASE | PAUSED | CREATED | SUMMARY |
| -- | ------- | ---- | ----- | ------ | ------- | ------- |
| 0001 | standalone-hyperlite | `docs/specs/0001-standalone-hyperlite` | deliver | no | 2026-07-26 | Extract Hyperlite into an independent Go CLI and native macOS application with direct, bounded project scanning. |
| 0002 | command-palettes | `docs/specs/0002-command-palettes` | deliver | no | 2026-07-27 | Add keyboard navigation, safe worktree pruning, concise hover context, and native ghost branding. |
| 0003 | inferred-attention | `docs/specs/0003-inferred-attention` | deliver | no | 2026-07-28 | Reconstruct evidence-backed goal threads and surface only material coordination changes without user bookkeeping. |
| 0004 | open-pull-requests | `docs/specs/0004-open-pull-requests` | deliver | no | 2026-07-29 | Track every open pull request across configured projects through a separate rate-safe informational projection. |

## PROJECT INTENT

Hyperlite is a fast native attention surface for the selected software
projects competing for consideration. It reconstructs goal threads from
durable Git, GitHub, and repository-memory evidence, preserves their complete
coordination lifecycle, and keeps ordinary artifact motion distinct from
changes that warrant human attention.

## GLOBAL CONSTRAINTS

- `docs/CONSTITUTION.md` is the canonical project contract.
- Each `docs/specs/<feature>/SPEC.md` is the canonical feature artifact; it
  wins whenever this index disagrees with it.
- The progress summary advances with a feature's highest completed
  evidence-backed phase.
- Hyperlite remains a projection over project evidence, not a second
  user-maintained project-management system.

## FEATURE SUMMARIES

### standalone-hyperlite

- **STATUS**: deliver
- **PAUSED**: no
- **INTENT**: Ship the focused attention window independently from Beacon.
- **APPROACH**: Own a bounded Go scanner, one-time configuration migration,
  universal native app bundle, and explicit refresh lifecycle.
- **OPEN ITEMS**: Implementation was delivered through issue #1 and PR #2; no
  implementation items remain.
- **POINTERS**: `docs/specs/0001-standalone-hyperlite/SPEC.md`

### command-palettes

- **STATUS**: deliver
- **PAUSED**: no
- **INTENT**: Keep the main surface quiet while making navigation and safe
  cleanup quickly reachable.
- **APPROACH**: Add pure palette interaction models, retain structured scan
  diagnostics in CLI/JSON, expose verified repository-scoped worktree pruning
  only when actionable, and provide lean hover context and native ghost
  branding.
- **OPEN ITEMS**: Implementation was delivered through issue #5 and PR #6; no
  implementation items remain.
- **POINTERS**: `docs/specs/0002-command-palettes/SPEC.md`

### inferred-attention

- **STATUS**: deliver
- **PAUSED**: no
- **INTENT**: Organize parallel threads of thought and implementation so
  consequential decisions, implications, dependencies, and obligations are
  not lost.
- **APPROACH**: Correlate exact evidence into stable threads, derive lifecycle
  and closure conservatively, add cited bounded local-model synthesis, persist
  fail-soft presentation state, and preserve material Attention behind a
  native feature boundary. The current native surface disables that
  presentation to focus on open PRs and a regular-text notepad. Keep a stable
  project map directly after Open PRs with every configured checkout and only
  subordinate lanes whose exact branch has a current open PR.
- **OPEN ITEMS**: Core inference merged through issue #7 and PR #8. Re-enabling
  its native presentation is intentionally deferred.
- **POINTERS**: `docs/specs/0003-inferred-attention/SPEC.md`

### open-pull-requests

- **STATUS**: deliver
- **PAUSED**: no
- **INTENT**: Keep one current, quiet index of every open pull request across
  configured projects without turning artifact presence into attention.
- **APPROACH**: Resolve configured GitHub repositories locally, retrieve
  all-author open pull requests in bounded GraphQL batches, keep an independent
  private cache with a five-minute success and failure floor, compose Open PRs
  and Projects in one scrolling native region, and use current exact PR head
  branches to hide cached, unavailable, merged, or closed worktree lanes.
- **OPEN ITEMS**: The initial projection merged through issue #9 and PR #10;
  the focused native layout and merged-lane follow-up merged through issue #11
  and PR #12. Repository-column prioritization merged through issue #13 and PR
  #14. Single-column active project lanes are complete locally on issue #15;
  ready pull-request review and merge remain.
- **POINTERS**: `docs/specs/0004-open-pull-requests/SPEC.md`

## LAST UPDATED

- 2026-07-29: Grouped fresh active project branches and worktrees in one column
  directly after the Open PRs list.
- 2026-07-29: Prioritized readable repository names over long pull-request
  titles in the aligned Open PRs row layout.
- 2026-07-29: Focused the native surface on plain-text notes and Open PRs,
  temporarily hid inferred-attention presentation, and made successful PR
  refreshes remove merged or closed worktree lanes from Projects.
- 2026-07-29: Added the rate-safe configured-project Open PRs projection above
  the stable Projects map.
- 2026-07-29: Recorded inferred-attention delivery through merged PR #8.
- 2026-07-29: Unified native typography on JetBrainsMono Nerd Font with a safe
  monospaced fallback and flattened the complete header into one line.
- 2026-07-29: Replaced the inferred current-work ledger with a stable,
  bottom-anchored map of configured projects and exact current local lanes.
- 2026-07-29: Added a local, debounced global notepad beneath the fixed header
  without allowing its contents to affect inferred threads or attention.
- 2026-07-29: Anchored the native header and separated urgent Attention from
  a bottom-anchored informational active-thread ledger.
- 2026-07-29: Removed the native scan-diagnostics control and retained only
  actionable stale-worktree pruning in Command-K.
- 2026-07-28: Added feature `0003-inferred-attention` and reconciled the
  project index with all current canonical specifications.
