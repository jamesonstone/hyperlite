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
from Git, GitHub, and Kit repository memory. It keeps active work and the
decisions around it visible without requiring another project-management
system.

<!-- BEGIN KIT-MANAGED README BADGES -->
[![Last commit](https://img.shields.io/github/last-commit/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/commits) [![Open issues](https://img.shields.io/github/issues/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/issues) [![Pull requests](https://img.shields.io/github/issues-pr/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/pulls) [![CI](https://github.com/jamesonstone/hyperlite/actions/workflows/ci.yml/badge.svg)](https://github.com/jamesonstone/hyperlite/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/releases)
<!-- END KIT-MANAGED README BADGES -->

## Quick start

```sh
make hyper
```

On its first run, Hyperlite adopts an existing Beacon configuration when
available. Select repositories with `hyperlite projects`, or scan a source path
directly with `hyperlite scan /path/to/projects`.

## Highlights

- A compact evidence Dashboard plus a full bounded spatial Pinboard for private
  graphical working memory
- Pinned and daily notes, open pull requests, and configured projects in the
  preserved Dashboard workspace
- Read-only GitHub quota, review-feedback, merge-conflict, and pinned Codex task visibility
- A grouped live Agent Tasks workspace plus an optional Mac notch/top-edge
  companion with exact, capability-gated response controls
- CLI and JSON interfaces for project scanning and inferred attention
- Local, permission-restricted state with no external project-management system

## Documentation

See the [user guide](docs/USER_GUIDE.md) for application behavior, keyboard
shortcuts, CLI commands, persistence paths, and the status and attention model.

## Development

```sh
make fmt-check vet test test-race build macos-test macos-build
```

The agent-session surface is enabled by default. Build and launch it with:

```sh
make macos-build
build/Hyperlite.app/Contents/MacOS/Hyperlite
```

Set the retained preview variable to zero for an explicit local rollback:

```sh
HYPERLITE_AGENT_SESSIONS_PREVIEW=0 build/Hyperlite.app/Contents/MacOS/Hyperlite
```

## Maintainers

Maintained with 🪖 and ❤️ by [Jameson](https://github.com/jamesonstone) (`jamesonstone`).
