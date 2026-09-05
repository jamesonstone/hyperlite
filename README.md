```text
██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗     ██╗████████╗███████╗
██║  ██║╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗██║     ██║╚══██╔══╝██╔════╝
███████║ ╚████╔╝ ██████╔╝█████╗  ██████╔╝██║     ██║   ██║   █████╗
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══╝  ██╔══██╗██║     ██║   ██║   ██╔══╝
██║  ██║   ██║   ██║     ███████╗██║  ██║███████╗██║   ██║   ███████╗
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝   ╚══════╝

                         fast attention for active Git work
```

Hyperlite is a standalone macOS window and CLI for notes, open pull requests,
and bounded local git maintenance. CLI and JSON interfaces still reconstruct
goal threads from Git, GitHub, and Kit repository memory when you ask for them.

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

- A fast native window for pinned and daily notes plus open pull requests
- Header actions to fast-forward configured default branches and to open
  interactive `git wt sweep`
- Read-only GitHub quota, review-feedback, and merge-conflict visibility
- CLI and JSON interfaces for project scanning and inferred attention
- Local, permission-restricted state with no external project-management system

## Documentation

See the [user guide](docs/USER_GUIDE.md) for application behavior, keyboard
shortcuts, CLI commands, persistence paths, and the status and attention model.

## Development

```sh
make fmt-check vet test test-race build macos-test macos-build
```

The native window is enabled by default. Build and launch it with:

```sh
make macos-build
build/Hyperlite.app/Contents/MacOS/Hyperlite
```

## Maintainers

Maintained with 🪖 and ❤️ by [Jameson](https://github.com/jamesonstone) (`jamesonstone`).
