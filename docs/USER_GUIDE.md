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

The release presentation has three full-content workspaces beneath one shared
header. Dashboard keeps the existing notes, open pull requests, and projects
surface. Pinboard is a separate private spatial-notes surface. Agent Tasks shows
ephemeral local coding-agent activity. Use the compact segmented control beside
the Hyperlite title or `Command+1`, `Command+2`, and `Command+3` to switch
without changing Dashboard data or preferences.

Inferred attention remains available through CLI and JSON but is hidden behind
a single native feature flag: the window, menu bar, and palettes show no thread
or attention counts or entries, and the app skips remote attention enrichment.

The fixed header contains the product name and ghost, the workspace switch,
compact pinned Codex task and GitHub GraphQL quota indicators, a subtly orange
Refresh action, and Settings. In Dashboard, Notes, Open PRs, and the
single-column Projects list each own one third of the content workspace. Every
section has its own vertical scroll boundary, so long notes, a large
pull-request index, and a dense project map remain independently usable.
Pull-request rows and header projections are informational only: none
establishes thread activity or attention. Refresh updates its existing remote
and scanned projections; it does not refresh the local Pinboard.

### Pinned Codex tasks

Pinned Codex tasks are a separate read-only operator projection. Hyperlite uses
a valid Desktop `pinned-thread-ids` array as membership authority and enriches
those opaque IDs from read-only SQLite metadata when available. The popover
preserves the authoritative count when metadata is incomplete and shows
unavailable instead of a stale or guessed count when membership cannot be read.

Pinned tasks load at startup, recheck changed source signatures after foreground
activation, and join explicit Refresh actions. Hyperlite does not poll or watch
Codex files, read transcripts, navigate to tasks, or mutate Codex state.

### Agent Tasks

The agent-session surface is a separate local runtime projection. It does not
change pinned Codex membership, inferred project threads, project attention,
or any repository. A Go helper owns exact session identity, provider ingress,
redaction, response revision checks, expiry, and routing-only persistence. The
native app consumes versioned sanitized snapshots.

Agent Tasks is the third full-window workspace after Pinboard. It shows only
current starting, processing, approval, input, or idle work and groups those
rows by exact client profile, so clients such as Claude Code and Cursor remain
separate even when they share an integration adapter. Recent completions,
errors, ended rows, and metadata-only verification rows do not appear there.
There is no floating notch or Agent Island panel.

On first agent-session launch, a centered welcome offers Enable Recommended,
Review in Settings, and Not Now. Hyperlite performs one bounded detection-only
request to describe installed clients, but does not start the long-running
session service, provider watchers, or Codex app server until the operator
makes a choice. Recommended includes only detected local clients. Ongoing
provider toggles and integration health live in grouped Settings. Shared
provider files retain unrelated settings; malformed, oversized, symlinked,
wrong-owner, concurrently created, or concurrently changed configuration fails
closed. Disabling an integration removes only exact Hyperlite-owned material.
Each detected provider also has an on-demand Verify action. Verification sends
one metadata-only synthetic event through Hyperlite's private bridge, socket,
store, and native decoder, then removes the synthetic row immediately. It
does not contact a model, invoke a provider task, or approve anything.

The Agent Tasks workspace may show at most six
recent user/assistant messages, each capped at 2,000 characters, plus an 8,000-
character latest final result or decision context. Native system typography is
used for chrome and controls, while technical content remains monospaced.
Internal reasoning, arbitrary historical tool output, raw hook payloads,
secrets, and generic environment data are excluded before state reaches the UI.

Codex tasks running in another process may appear as `notLoaded` to Hyperlite's
own app server. Hyperlite keeps that status unknown, uses only an exact safe
rollout path to start one of a bounded number of incremental observers, and
creates a row only after the rollout establishes exact session identity and
runtime phase. Stored thread listings alone never create a live or idle row.
Hyperlite also watches the current local Codex date directory so a new
hookless rollout created after launch can appear without polling. Rollouts are
read incrementally in bounded chunks, recover from truncation or replacement,
and retain a watcher only while that exact session still needs observation.
Foreground activation requests discovery only after the prior discovery is
stale; the explicit Refresh control always requests it.

The Codex app server is an adaptive discovery client rather than an
always-running child. Hyperlite owns at most one stdio child, reuses it across
bounded refreshes, and stops it after 120 seconds without discovery or live
response work. Hooks and file events continue tracking after it exits.

Allow Once, Deny, and Answer appear only for a current exact request with
complete redacted context and a live blocking provider channel. Rollout-only,
notify-only, stale, truncated, or redacted requests offer Open in client
instead. Hyperlite never simulates session scope by repeatedly approving
individual requests. A session can retain at most eight independent requests.
The current request is shown with the total pending count; resolving or
retracting it reveals the next request without changing any other request. A
response submits once for its exact provider, session, request ID, and action
revision; stale answer text is cleared when that identity changes. Routing
buttons name the real capability, such as Open Codex or Reveal in Finder,
instead of claiming an unavailable client route.

Completed sessions remain for ten minutes. Other non-attention sessions expire
after thirty minutes of inactivity, unresolved attention does not age-expire,
and content disappears when the session expires or Hyperlite exits. Only
provider/profile IDs, opaque session ID, working directory, app/terminal/tmux
routing identifiers, and last-seen time may persist, for at most twenty-four
hours.

The runtime is deliberately bounded for indefinite use: at most 32 rollout
watchers, 100 session rows, eight requests per session, six display messages,
and 256 content-free phase transitions. Ordinary UI snapshots are coalesced to
four per second during bursts; attention, input, and error remain immediate.
There are no background self-tests, continuous UI timelines, transcript
rescans, or periodic project scans.

Sounds and native notifications are opt-in in Settings. Notifications contain
only profile and project metadata. Agent sessions are enabled by default. Set
the retained preview variable to zero for an explicit local rollback:

```sh
make macos-build
HYPERLITE_AGENT_SESSIONS_PREVIEW=0 build/Hyperlite.app/Contents/MacOS/Hyperlite
```

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
standard Apple Silicon and Intel Homebrew binary directories so Finder launches
can resolve an installed `gh` executable.

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

### Projects and worktrees

Projects always shows every configured checkout. Registered subordinate
worktrees appear only when their exact case-sensitive branch is the head branch
of a current open pull request for that project. Detached worktrees never appear
as active even if their metadata retains a matching branch. Cached or
unavailable pull-request data does not retain a subordinate worktree as active.

After a successful refresh observes that pull request as merged or closed, its
worktree row disappears. Hyperlite never deletes or prunes the local checkout.

Each project can collapse to a primary-branch summary. The quiet title-line
controls collapse or expand the presented projects, filter the loaded map,
choose a sort, or enter reorder mode. Filters temporarily expand matches without
erasing saved collapse state. Sort, collapse, and committed custom order persist
locally; they never rewrite project configuration. Reorder uses the same
drag-handle, Done/Cancel, and accessible Move action model as Open PRs.

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

Pinboard is one private, finite spatial workspace, not a Kanban workflow or an
infinite drawing canvas. Its toolbar creates notes and sections and opens the
recoverable archive. The board scrolls horizontally or vertically only when
its fixed bounds exceed the visible window; it has no zoom, connectors,
auto-layout, collaboration, background indexing, or automatic status changes.

A section is a titled rectangular region with a stable identity. Use its title
or context menu to rename it, its header handle to move it, and its lower-right
handle to resize it within the board. Both handles are keyboard focusable;
arrow keys nudge the focused move handle or adjust the focused resize handle,
and the same directions are available as accessibility actions. The section
`+` creates a note directly
inside that section. Adding a note without a focused section uses the sole
section or presents a destination chooser. An empty section requires
confirmation before deletion. A nonempty section can be cancelled, emptied
manually, or explicitly deleted with all contained notes moved into Archive;
it never silently destroys them.

Each fixed-size card has a required single-line title and a multiline plain
Markdown-compatible description. Clicking the card opens an explicit
Save/Cancel editor with read-only Created and Updated timestamps. Use the quiet
card context menu or accessibility actions to Edit, Fork, or Delete. The small
header grip drags a card freely inside its section; crossing another section
reparents and clamps it there. Focus a card and use the arrow keys or its
directional accessibility actions to nudge it without a pointer. Moving or
resizing layout never changes Updated.

Fork creates an independent note with copied content, a new opaque identity,
new Created and Updated timestamps, retained source lineage, and a visible
clamped cascade offset. Delete is recoverable: it removes the card from the
active layout and records its original section and archive time. Archive can
restore it to that section while it exists or to an explicitly selected
destination after the original section is gone. Pinboard has no permanent
delete action in this version.

Pinboard content is local graphical working memory only. It is never searched
as Notepad/Daily content and never becomes project evidence, thread or
attention state, PR state, project configuration, task synchronization, or
agent input.

### Keyboard shortcuts

- `Command+1` shows Dashboard.
- `Command+2` shows Pinboard.
- `Command+3` shows Agent Tasks unless agent sessions were explicitly disabled.
- `Command+R` refreshes the focused Hyperlite application.
- `Command+K` opens a searchable command palette with Show Dashboard, Show
  Pinboard, Show Agent Tasks, Add Pinboard Note,
  Add Pinboard Section, Open Pinboard Archive, Refresh, Force Cache Refresh,
  Copy Open PR Merge Prompt, Settings, Add Project, Remove Project, and
  exact or on-device semantic matches from pinned and daily note filenames,
  dates, and contents.
  Force Cache Refresh retries every configured GitHub repository regardless of
  cache age so a successful check replaces stale cached errors. Copy Open PR
  Merge Prompt copies the same durable merge-ready prompt as the Open PRs
  header for the currently visible rows and stays open to confirm the copy.
  Selecting a
  pinned result opens Notepad; selecting a daily result opens the matching
  Daily date.
- `Command+P` opens the same searchable surface in configured-project mode.
  Projects start collapsed and expand to show their open pull requests and
  registered branch or worktree lanes.

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
hyperlite projects add /path/to/repository
hyperlite projects remove /path/to/repository
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

The Pinboard follows the same private app-data root at
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
