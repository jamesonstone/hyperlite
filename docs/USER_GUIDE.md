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

The current native presentation focuses on notes and open pull requests.
Inferred attention remains available through CLI and JSON but is hidden behind
a single native feature flag: the window, menu bar, and palettes show no thread
or attention counts or entries, and the app skips remote attention enrichment.

The fixed header contains the product name and ghost, compact pinned Codex task
and GitHub GraphQL quota indicators, a subtly orange Refresh action, and
Settings. Notes, Open PRs, and the single-column Projects list each own one
third of the content workspace. Every section has its own vertical scroll
boundary, so long notes, a large pull-request index, and a dense project map
remain independently usable. Pull-request rows and header projections are
informational only: none establishes thread activity or attention.

### Pinned Codex tasks

Pinned Codex tasks are a separate read-only operator projection. Hyperlite uses
a valid Desktop `pinned-thread-ids` array as membership authority and enriches
those opaque IDs from read-only SQLite metadata when available. The popover
preserves the authoritative count when metadata is incomplete and shows
unavailable instead of a stale or guessed count when membership cannot be read.

Pinned tasks load at startup, recheck changed source signatures after foreground
activation, and join explicit Refresh actions. Hyperlite does not poll or watch
Codex files, read transcripts, navigate to tasks, or mutate Codex state.

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
per repository. Refresh forces the index current.

Failed checks retain visibly cached rows. A project with no usable GitHub
identity or cache is shown as unavailable. Pagination fails safely on a
repeated cursor or bounded page limit instead of risking an unbounded GitHub
query loop.

Each row places an actionable review-feedback count after its ready or draft
state. Only unresolved, non-outdated GitHub review threads count. Nonzero counts
use the orange attention color, confirmed zero uses a quiet dash, and
unavailable legacy cache data uses `?` until a complete refresh supplies an
exact count. The entire row remains a link to the pull request.

### Projects and worktrees

Projects always shows every configured checkout. Registered subordinate
worktrees appear only when their exact case-sensitive branch is the head branch
of a current open pull request for that project. Detached worktrees never appear
as active even if their metadata retains a matching branch. Cached or
unavailable pull-request data does not retain a subordinate worktree as active.

After a successful refresh observes that pull request as merged or closed, its
worktree row disappears. Hyperlite never deletes or prunes the local checkout.

### Notepad

The Notepad directly beneath the header is private operator memory, not another
source of project truth. One permanent Pinned editor is always visible beside
one dated Daily editor. Daily opens today by default and creates a missing file
only after the first edit.

Previous, next, today, and date-picker controls open daily notes directly. The
clickable Notepad title offers Today, Yesterday, and up to ten recently modified
daily files. Typing stays in memory, the latest edit saves after three idle
seconds, and pending text flushes when the window or application yields.

Both editors contain regular UTF-8 text rendered with JetBrainsMono Nerd Font
through the shared application resolver and a system monospaced fallback. They
do not render Markdown or feed content into thread inference or attention.

### Keyboard shortcuts

- `Command+R` refreshes the focused Hyperlite application.
- `Command+K` opens a searchable command palette with Refresh, Settings, Add
  Project, Remove Project, and exact or on-device semantic matches from pinned
  and daily note filenames, dates, and contents. Selecting a note focuses
  Pinned or opens the matching daily date.
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
