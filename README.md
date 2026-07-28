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
The configured local Ollama model may synthesize cited rationale,
implications, obligations, and relationships, but it cannot merge threads or
establish completion.

Attention is a material change in coordination: a decision, durable direction
change, dependency, operational obligation, consequential delivery boundary,
architectural review challenge, closure gap, or evidence conflict. Commits,
dirty counts, CI churn, routine review repairs, and agent lifecycle activity
remain artifact progress. A merged PR advances a goal; it does not complete a
goal that still has delivery, deployment, infrastructure, or reflection work.

The native window loads cached state and current local Git evidence first. It
refreshes remote evidence on foreground activation only when stale, and then
runs optional local inference. The menu-bar ghost counts threads with unseen
attention, not artifacts. Active threads remain visible regardless of age;
only completed threads use the configured recent-work window.

Open a thread to see its goal, rationale, progress, dependencies, implications,
remaining obligations, evidence, and optional note. Opening marks material
moments through the displayed revision as seen without hiding the thread.
Command+K navigates commands and threads; Command+P navigates projects and
their threads. Diagnostics and verified stale-worktree pruning remain
available from the header.

The JSON and local-inference interfaces are:

```sh
hyperlite --json
hyperlite infer --json
hyperlite thread seen <thread-id> --revision <digest>
hyperlite thread note <thread-id> --stdin
```

Thread state is stored atomically with user-only permissions at
`$XDG_STATE_HOME/hyperlite/threads.json`, or
`~/.local/state/hyperlite/threads.json` by default. Notes and seen state are
presentation metadata; neither can create or complete a thread.

## Development

```sh
make fmt-check vet test test-race build macos-test macos-build
```

`make hyper` builds `build/Hyperlite.app`, stops a prior running Hyperlite
process, then opens the fresh windowed app.

## Maintainers

Maintained with 🪖 and ❤️ by [Jameson](https://github.com/jamesonstone) (`jamesonstone`).
