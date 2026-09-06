# User guide

Hyperlite combines a native macOS workspace with CLI and JSON interfaces for
inspecting active Git work. This guide covers its user-facing behavior and
local data boundaries.

## Launch and configuration

```sh
make hyper
```

This builds `build/Hyperlite.app`, stops a prior running Hyperlite process, and
opens the fresh windowed app.

The first default run copies `~/.config/beacon/config.yaml` directly to
`~/.config/hyperlite/config.yaml` when Hyperlite does not already own a config.
Later runs use only the Hyperlite copy. Select projects with `hyperlite projects`
or scan a source path directly with `hyperlite scan /path/to/projects`.

## Native workspace

The native app is one window: Notepad/Daily above Open PRs. Launch always
opens that window. It does not start a menu bar extra, workspace switcher,
Projects map, Pinboard, Agent Tasks, Agent Island, or pinned Codex surface.
The default Control+Shift+H hotkey brings the window forward; becoming
active still refreshes stale Open PRs, but the hotkey itself does not force
GitHub work. Command-P, Remove Project, and Settings load the configured
project list when opened, not at launch. Command-K indexes note text for
literal search immediately and loads on-device sentence embeddings only
when a query has no exact match.

Inferred attention remains available through CLI and JSON but is hidden from
the window. Launch and Refresh do not scan inferred threads. Refresh updates
Open PRs and the current daily-note date. The header keeps the product name
and ghost, GitHub GraphQL quota, Update Default Branches, Sweep Worktrees, a
subtly orange Refresh action, and Settings.

Configured repositories still determine which Open PRs appear and which
default branches Update Default Branches can fast-forward. Add or remove them
from Settings or Command-K. Command-P is a cheap lookup of those repositories
and their loaded pull requests; it is not a dashboard map.

### GitHub quota

Existing GraphQL requests also return the caller's quota metadata, so the
header indicator adds no request or `gh` process. It shows calls used out of
the limit. Hover exposes remaining capacity, local reset and observation times,
and the last query's cost and node count; clicking pins the same details until
another click or native dismissal.

Only complete observations replace the separately cached quota snapshot.
Healthy capacity stays quiet, 20 percent remaining warns in orange, and 10
percent remaining is critical in red. Once two valid observations exist in the
same reset window, the popover shows the trailing quota-point burn rate, sample
duration, projected depletion time, and whether depletion falls before or
after reset. Reset crossings, counter decreases, and samples shorter than one
minute remain explicitly measuring rather than projecting.

### Open pull requests

Open PRs load from a separate private cache. Hyperlite refreshes stale
configured repositories on startup or foreground activation no more often than
every five minutes and uses bounded GraphQL batches instead of one `gh` process
per repository. Refresh forces the index current; Force Cache Refresh in
Command-K retries only this cache without refreshing unrelated projections.
The packaged app preserves its inherited executable search path and adds the
standard Apple Silicon and Intel Homebrew directories plus `~/.local/bin` so
Finder launches can resolve `gh` and `git-wt`.

Failed checks retain visibly cached rows. A project with no usable GitHub
identity or cache is shown as unavailable. Pagination fails safely on a
repeated cursor or bounded page limit instead of risking an unbounded GitHub
query loop.

Each row places a merge-conflict icon after its ready or draft state when
GitHub reports the pull request as `CONFLICTING`. The column stays aligned when
there is no confirmed conflict; `MERGEABLE`, `UNKNOWN`, and older cache entries
without the field stay blank. VoiceOver names confirmed conflicts only and
omits unconfirmed `MERGEABLE`, `UNKNOWN`, and legacy rows. The actionable
review-feedback count follows that column. Only unresolved, non-outdated GitHub review threads count. Nonzero counts
use the orange attention color, confirmed zero uses a quiet dash, and
unavailable legacy cache data uses `?` until a complete refresh supplies an
exact count. The row content opens the pull request; its separate leading
checkbox, immediately before the repository name, changes only the private
`Reviewed by me` marker.

A review mark is stored locally for the exact observed head commit and survives
relaunches. Marked rows stay in place and become subtly muted. When current
GitHub evidence reports a new head commit, Hyperlite restores normal emphasis
and shows an orange stale marker until the new revision is reviewed or the mark
is cleared. Cached or unavailable evidence preserves the last mark; a cached
row may clear that mark but cannot create or replace one.

The quiet icons on the Open PRs title line copy a merge-ready coding-agent
prompt for the currently visible rows, hide drafts, filter the loaded
index, choose a sort order, clear all local review marks, or enter reorder
mode. The title shows the count currently reviewed. Copy writes a durable
instruction plus each visible pull request's identity, URL, draft/ready
state, confirmed merge-conflict hint or `merge conflicts not confirmed`,
and unresolved review-thread count to the clipboard, then confirms for two
seconds. It does not call `gh`, open
GitHub, or mutate pull requests. An empty visible list disables the control
and leaves the clipboard unchanged. The hide-drafts checkbox
removes draft rows from the visible list without changing the cached index;
it is a temporary presentation toggle like other Open PRs filters and never
queries GitHub. Filters include local Unreviewed, Reviewed, and
Stale states; they are temporary and never refresh GitHub. Sort choices persist.
Reorder shows every loaded row with drag handles, including drafts even while
hide-drafts is on; Done saves a custom order, while Cancel restores the previous
order. Accessible Move up and Move down actions provide the same control without
dragging. Copy in reorder mode uses that same on-screen list.

`Reviewed by me` is organization metadata, not GitHub approval, review-feedback
resolution, passing checks, mergeability, or permission to merge. Hyperlite
does not post a comment, label, or review. A merge operator or coding agent must
still refresh and verify the exact head, feedback, checks, conflicts, protection
rules, and final merged state.

### Local git maintenance

Update Default Branches fetches each configured repository, then fast-forwards
that repository's default branch when Git allows a clean fast-forward. If the
working tree is dirty, the history is not a fast-forward, or Git refuses to
update a checked-out ref, Hyperlite skips that repository and reports why. It
never resets, stashes, force-updates, or deletes branches.

Sweep Worktrees opens Terminal running interactive `git wt sweep`. Hyperlite
does not pass `--auto` and does not delete worktrees itself; confirmation stays
in `git-wt`.

Command-P lists configured repositories and can expand loaded open pull
requests. It does not present a dashboard project map.

### Notepad

The Notepad directly beneath the header is private operator memory, not another
source of project truth. Its compact tab row keeps the permanent Notepad
separate from `Daily: <formatted date>` with both a vertical divider and active
tab styling. Daily opens today by default; selecting Notepad opens the durable
note, and selecting Daily returns to the current dated note.

Daily continues following the current calendar day while Hyperlite remains
open. Calendar-day, system-clock, and time-zone changes move it without
polling; foreground activation and explicit refresh recover a missed change.
Choosing a historical date pauses that rollover until today is selected again
from the calendar.

The single larger chevron to the left of Notepad opens the native calendar.
Selecting a date activates Daily and directly loads that note after safely
flushing a pending daily edit. There are no previous/next, Today, right-side
date-field, or recent-ten-days controls. A missing daily file is created only
after the first edit.

The active editor contains regular UTF-8 text rendered with JetBrainsMono Nerd
Font through the shared application resolver and a system monospaced fallback.
It does not render Markdown or feed content into thread inference or attention.
Typing stays in memory, the latest edit saves after three idle seconds, and
pending text flushes when the window or application yields.

### Pinboard

The native window no longer opens Pinboard. The CLI `hyperlite pinboard`
commands and the private board store remain for existing local data.

### Keyboard shortcuts

- `Command+R` refreshes Open PRs and the current daily-note date.
- `Command+K` opens a searchable command palette with Refresh, Force Cache
  Refresh, Update Default Branches, Sweep Worktrees, Copy Open PR Merge Prompt,
  Settings, Add Project, Remove Project, and exact or on-device semantic
  matches from pinned and daily note filenames, dates, and contents.
  Force Cache Refresh retries every configured GitHub repository regardless of
  cache age so a successful check replaces stale cached errors. Copy Open PR
  Merge Prompt copies the same durable merge-ready prompt as the Open PRs
  header for the currently visible rows and stays open to confirm the copy.
  Selecting a pinned result opens Notepad; selecting a daily result opens the
  matching Daily date.
- `Command+P` opens the same searchable surface in configured-project mode.
  Projects start collapsed and expand to show loaded open pull requests.

Add Project is also available from Settings. Project selection changes are
written atomically by the bundled helper. Hyperlite does not expose
worktree-pruning functionality; scan diagnostics remain available through CLI
output and JSON.

## CLI reference

```sh
hyperlite --json
hyperlite infer --json
hyperlite pull-requests --json
hyperlite pull-requests --json --local
hyperlite pull-requests --json --force
hyperlite projects
hyperlite projects list [--json]
hyperlite projects add /path/to/repository
hyperlite projects remove /path/to/repository
hyperlite projects update-defaults [--json]
hyperlite notepad
hyperlite notepad show [--date YYYY-MM-DD] [--json]
hyperlite notepad set --stdin [--date YYYY-MM-DD] [--json]
hyperlite notepad path [--date YYYY-MM-DD]
hyperlite notepad index
hyperlite pinboard show
hyperlite pinboard mutate --stdin
hyperlite thread seen <thread-id> --revision <digest>
hyperlite thread note <thread-id> --stdin
```

## Local data

Thread state is stored atomically with user-only permissions at
`$XDG_STATE_HOME/hyperlite/threads.json`, or
`~/.local/state/hyperlite/threads.json` by default. Notes and seen state are
presentation metadata; neither can create or complete a thread.

The project pull-request cache is stored independently with user-only
permissions at `$XDG_STATE_HOME/hyperlite/pull-requests.json`, or
`~/.local/state/hyperlite/pull-requests.json` by default.

The Notepad uses the same atomic, user-only boundary beneath
`$XDG_DATA_HOME/hyperlite/notes`, or `~/.local/share/hyperlite/notes` by
default. The pinned note is `pinned.md`; daily notes are
`daily/YYYY-MM-DD.md`. On first use, Hyperlite adopts the prior `notepad.txt`
or default `notepad.md` document as the pinned note without changing its
content. Every document is limited to 256 KiB.

The CLI Pinboard store remains at
`$XDG_DATA_HOME/hyperlite/board`, or `~/.local/share/hyperlite/board` by
default. `board.json` contains only the schema, finite board and section
geometry, note membership, and note geometry. Active note content and metadata
use opaque filenames beneath `notes/<note-id>.md`; archived notes move to
`archive/<note-id>.md`. Title-derived paths are never used. Content files are
canonical for IDs, text, Created/Updated timestamps, fork lineage, and archive
metadata, so layout-only movement does not rewrite content recency. Loads and
mutations are bounded, locked, user-only, atomic per file, and fail closed on
unsafe, malformed, oversized, orphaned, or inconsistent state.

## Status and attention model

Hyperlite treats issues, active specs, pull requests, review threads, material
worktrees, and referenced operational documents as evidence for inferred goal
threads. Exact issue, branch, PR, spec, and link identifiers own membership.
Recent open pull requests are strong working-set evidence, but they are not
perpetual activity: an untouched ordinary pull request can become dormant,
while a still-supported material review decision keeps the thread current.

Issues and local Git state must be recent and corroborated by a selected
checkout or exact durable issue lane. Old issues, default-branch dirt, temporary
automation worktrees, and unrelated historical specs do not become active
threads. The configured local Ollama model may synthesize cited rationale,
implications, obligations, and relationships, but it cannot merge threads or
establish completion.

Attention is a material change in coordination: a decision, durable direction
change, dependency, operational obligation, consequential delivery boundary,
architectural review challenge, closure gap, or evidence conflict. Commits,
dirty counts, CI churn, routine review repairs, and agent lifecycle activity
remain artifact progress. Boundary attention requires an actionable
consequential change, not a negative safety statement or incidental keyword.

A surfaced moment states the expected cognitive action, consequence, and
condition that keeps it valid. Hyperlite re-evaluates that claim on every scan;
unsupported, superseded, or missing evidence retracts attention without
requiring acknowledgement. Once seen, the same supported situation stays
acknowledged across unrelated evidence refreshes. Only a changed coordination
situation can demand attention again.

A merged PR advances a goal; it does not complete a goal that still has
delivery, deployment, infrastructure, or reflection work.
