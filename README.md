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
The fixed header contains only the product name, Refresh, and Settings. Open
PRs and Projects share the scrolling content region below the notepad, with
the single-column Projects list immediately following the final PR row. The
pull-request index is informational only: it never establishes thread activity
or attention.

Open PRs load from a separate private cache, refresh stale configured
repositories on startup or foreground activation no more often than every five
minutes, and use bounded GraphQL batches instead of one `gh` process per
repository. The existing Refresh action forces the index current. Failed checks
retain visibly cached rows; a project with no usable GitHub identity or cache is
shown as unavailable. Pagination fails safely on a repeated cursor or bounded
page limit instead of risking an unbounded GitHub query loop.

Projects always shows every configured checkout. Registered subordinate
worktrees appear only when their exact case-sensitive branch is the head branch
of a current open pull request for that project. Cached or unavailable
pull-request data does not retain a subordinate worktree as active. After a
successful refresh observes that pull request as merged or closed, its
worktree row disappears; Hyperlite never deletes or prunes the local checkout.

The global notepad directly beneath the header is a local scratch surface, not
another source of project truth. Typing stays in memory, the latest edit saves
after three idle seconds, and pending text flushes when the window or
application yields. It is regular UTF-8 text rendered in the proportional
system font, with no Markdown presentation. Its content never enters thread
inference or attention.

Command+K navigates current commands. Verified stale-worktree pruning appears
there when applicable; scan diagnostics remain available through CLI output and
JSON. Thread and project navigation can be re-enabled with the native attention
presentation later.

The JSON and local-inference interfaces are:

```sh
hyperlite --json
hyperlite infer --json
hyperlite pull-requests --json
hyperlite pull-requests --json --local
hyperlite pull-requests --json --force
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
