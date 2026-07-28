# PROJECT PROGRESS SUMMARY

## FEATURE PROGRESS TABLE

| ID | FEATURE | PATH | PHASE | PAUSED | CREATED | SUMMARY |
| -- | ------- | ---- | ----- | ------ | ------- | ------- |
| 0001 | standalone-hyperlite | `docs/specs/0001-standalone-hyperlite` | deliver | no | 2026-07-26 | Extract Hyperlite into an independent Go CLI and native macOS application with direct, bounded project scanning. |
| 0002 | command-palettes | `docs/specs/0002-command-palettes` | deliver | no | 2026-07-27 | Add keyboard navigation, compact diagnostics, safe worktree pruning, concise hover context, and native ghost branding. |
| 0003 | inferred-attention | `docs/specs/0003-inferred-attention` | deliver | no | 2026-07-28 | Reconstruct evidence-backed goal threads and surface only material coordination changes without user bookkeeping. |

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
- **INTENT**: Keep the main surface quiet while making navigation,
  diagnostics, and safe cleanup quickly reachable.
- **APPROACH**: Add pure palette interaction models, compact diagnostics,
  verified repository-scoped worktree pruning, lean hover context, and native
  ghost branding.
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
  fail-soft presentation state, and render Attention, In Flight, and recent
  completed sections.
- **OPEN ITEMS**: Implementation and local validation are complete on issue
  #7 and branch `GH-7`; ready pull-request review and merge remain.
- **POINTERS**: `docs/specs/0003-inferred-attention/SPEC.md`

## LAST UPDATED

- 2026-07-28: Added feature `0003-inferred-attention` and reconciled the
  project index with all current canonical specifications.
