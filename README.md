```text
██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗     ██╗████████╗███████╗
██║  ██║╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗██║     ██║╚══██╔══╝██╔════╝
███████║ ╚████╔╝ ██████╔╝█████╗  ██████╔╝██║     ██║   ██║   █████╗
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══╝  ██╔══██╗██║     ██║   ██║   ██╔══╝
██║  ██║   ██║   ██║     ███████╗██║  ██║███████╗██║   ██║   ███████╗
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝   ╚══════╝

                         fast attention for active Git work
```

Hyperlite is a standalone macOS window and CLI that reconstructs goal threads
from Git, GitHub, and Kit repository memory. It keeps parallel work,
dependencies, operational obligations, and consequential changes visible
without requiring a second project-management system.

<!-- BEGIN KIT-MANAGED README BADGES -->
[![Last commit](https://img.shields.io/github/last-commit/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/commits) [![Open issues](https://img.shields.io/github/issues/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/issues) [![Pull requests](https://img.shields.io/github/issues-pr/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/pulls) [![Release](https://img.shields.io/github/v/release/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/releases)
<!-- END KIT-MANAGED README BADGES -->

## Quick start

```sh
make hyper
```

The first default run copies `~/.config/beacon/config.yaml` directly to
`~/.config/hyperlite/config.yaml` when Hyperlite does not already own a config.
Later runs use only the Hyperlite copy. Select projects with `hyperlite projects`
or scan a source path directly with `hyperlite scan /path/to/projects`.

## Status model

Hyperlite treats issues, active specs, pull requests, review threads, material
worktrees, and referenced operational documents as evidence for inferred goal
threads. Exact issue, branch, PR, spec, and link identifiers own membership.
Recent open pull requests are strong working-set evidence, but they are not
perpetual activity: an untouched ordinary pull request can become dormant,
while a still-supported material review decision keeps the thread current.
Issues and local Git state must be recent and corroborated by a selected
checkout or exact durable issue lane; old issues, default-branch dirt,
temporary automation worktrees, and unrelated historical specs do not become
active threads.
The configured local Ollama model may synthesize cited rationale,
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
acknowledged across unrelated evidence refreshes; only a changed coordination
situation can demand attention again.
A merged PR advances a goal; it does not complete a goal that still has
delivery, deployment, infrastructure, or reflection work.

The current native presentation focuses on notes and open pull requests.
Inferred attention remains available through CLI/JSON but is hidden behind a
single native feature flag: the window, menu bar, and palettes show no thread
or attention counts or entries, and the app skips remote attention enrichment.
The fixed header contains the product name and ghost, a compact GitHub GraphQL
rate-limit indicator, a subtly orange Refresh action, and Settings. The
indicator shows calls used out of the caller's limit; hover exposes remaining
capacity, the local reset and observation times, and the last query's cost and
node count in a comfortably spaced, app-themed JetBrainsMono Nerd Font
popover. Clicking the indicator opens and pins the same details until another
click or native dismissal. Notes, Open PRs, and the single-column Projects list
each own one third of the content workspace. Every section has its own vertical
scroll boundary, so long notes, a large pull-request index, and a dense project
map remain independently usable. The pull-request index and quota display are
informational only: neither establishes thread activity or attention.

Open PRs load from a separate private cache, refresh stale configured
repositories on startup or foreground activation no more often than every five
minutes, and use bounded GraphQL batches instead of one `gh` process per
repository. The existing Refresh action forces the index current. Failed checks
retain visibly cached rows; a project with no usable GitHub identity or cache is
shown as unavailable. Pagination fails safely on a repeated cursor or bounded
page limit instead of risking an unbounded GitHub query loop. Every existing
GraphQL request also returns the caller's quota metadata, so the header adds no
request or `gh` process. Only complete observations replace the separately
cached quota snapshot; healthy capacity stays quiet, while 20 percent remaining
warns in orange and 10 percent remaining is critical in red. Each row places an
actionable review-feedback count after its ready/draft state: only unresolved,
non-outdated GitHub review threads count. Nonzero counts use the orange attention
color, confirmed zero uses a quiet dash, and unavailable legacy cache data uses
`?` until a complete refresh supplies an exact count. The entire row remains a
link to the pull request.

Projects always shows every configured checkout. Registered subordinate
worktrees appear only when their exact case-sensitive branch is the head branch
of a current open pull request for that project. Detached worktrees never
appear as active even if their metadata retains a matching branch. Cached or
unavailable pull-request data does not retain a subordinate worktree as active.
After a successful refresh observes that pull request as merged or closed, its
worktree row disappears; Hyperlite never deletes or prunes the local checkout.

The global notepad directly beneath the header is a local scratch surface, not
another source of project truth. Typing stays in memory, the latest edit saves
after three idle seconds, and pending text flushes when the window or
application yields. It is regular UTF-8 text rendered with JetBrainsMono Nerd
Font through the shared application resolver and a system monospaced fallback,
with no Markdown presentation. Its darker inset surface follows the existing
Selenized theme, and its content never enters thread inference or attention.

Command+R refreshes the focused Hyperlite application. Command+K opens a
searchable command palette with Refresh, Settings, Add Project, and Remove
Project. Command+P opens the same searchable surface in configured-project
mode; projects start collapsed and expand to show their open pull requests and
registered branch/worktree lanes. Add Project is also available from Settings.
Project selection changes are written atomically by the bundled helper.
Hyperlite does not expose worktree-pruning functionality; scan diagnostics
remain available through CLI output and JSON.

The JSON and local-inference interfaces are:

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
hyperlite notepad set --stdin
hyperlite notepad path
hyperlite thread seen <thread-id> --revision <digest>
hyperlite thread note <thread-id> --stdin
```

Thread state is stored atomically with user-only permissions at
`$XDG_STATE_HOME/hyperlite/threads.json`, or
`~/.local/state/hyperlite/threads.json` by default. Notes and seen state are
presentation metadata; neither can create or complete a thread.

The project pull-request cache is stored independently with user-only
permissions at `$XDG_STATE_HOME/hyperlite/pull-requests.json`, or
`~/.local/state/hyperlite/pull-requests.json` by default.

The global notepad is stored separately with the same atomic, user-only
boundary at `$XDG_DATA_HOME/hyperlite/notepad.txt`, or
`~/.local/share/hyperlite/notepad.txt` by default. On first use, Hyperlite
adopts the prior default `notepad.md` file without changing its content. The
document is limited to 256 KiB.

## Development

```sh
make fmt-check vet test test-race build macos-test macos-build
```

`make hyper` builds `build/Hyperlite.app`, stops a prior running Hyperlite
process, then opens the fresh windowed app.

## Maintainers

Maintained with 🪖 and ❤️ by [Jameson](https://github.com/jamesonstone) (`jamesonstone`).
