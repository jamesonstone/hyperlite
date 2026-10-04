```text
██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗     ██╗████████╗███████╗
██║  ██║╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗██║     ██║╚══██╔══╝██╔════╝
███████║ ╚████╔╝ ██████╔╝█████╗  ██████╔╝██║     ██║   ██║   █████╗
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══╝  ██╔══██╗██║     ██║   ██║   ██╔══╝
██║  ██║   ██║   ██║     ███████╗██║  ██║███████╗██║   ██║   ███████╗
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝   ╚══════╝

                         fast attention for active Git work
```

Hyperlite is a standalone macOS window and CLI that watches open pull requests
across your configured projects.

<!-- BEGIN KIT-MANAGED README BADGES -->
[![Last commit](https://img.shields.io/github/last-commit/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/commits) [![Open issues](https://img.shields.io/github/issues/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/issues) [![Pull requests](https://img.shields.io/github/issues-pr/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/pulls) [![CI](https://github.com/jamesonstone/hyperlite/actions/workflows/ci.yml/badge.svg)](https://github.com/jamesonstone/hyperlite/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/jamesonstone/hyperlite)](https://github.com/jamesonstone/hyperlite/releases)
<!-- END KIT-MANAGED README BADGES -->

## Quick start

```sh
make hyper
```

On its first run, Hyperlite adopts an existing Beacon configuration when
available. Select repositories with `hyperlite projects` (or `hyperlite
projects add <path>`), then list their open pull requests with `hyperlite
pull-requests`.

## Highlights

- A fast native window whose Open PRs list fills the window, grouped by
  configured project, with keyboard navigation and reviewed-by-me marks
- A header action to open interactive `git wt sweep`
- Read-only GitHub quota, review-feedback, and merge-conflict visibility
- Per-project workflow strips with a quota-governed poll that shows running
  GitHub Actions and deployments, plus Pulls and Actions links
- CLI and JSON interfaces for configured projects and open pull requests
- Local, permission-restricted state with no external project-management system

## Documentation

See the [user guide](docs/USER_GUIDE.md) for application behavior, keyboard
shortcuts, CLI commands, and persistence paths.

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
