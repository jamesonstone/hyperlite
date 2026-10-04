# Testing Reference

## Purpose

- Record the project's durable commands, suites, environments, automation, and evidence expectations
- Follow `rules/testing-and-environment-validation.md` for the mandatory cross-project testing and production-safety contract
- Keep feature-specific testing details in the current feature's `SPEC.md` VALIDATION and OUTCOME sections; legacy staged flows may still use `PLAN.md` or `TASKS.md`

## Current State

- Go package tests cover configuration, project discovery and selection, the
  Open PR index (including the concurrent probe-then-detail fetch with
  per-repository failure isolation), CLI commands, and failure behavior.
- Swift executable model tests and native type-checking cover schema and
  presentation behavior: Command-K entries (Theme and Font Size nested lists,
  without retired workspace actions), helper PATH including `~/.local/bin`,
  configured-project decoding, Open PR merge-conflict decoding and
  conflict-column layout, Copy Open PR Merge Prompt labels, hover
  what-and-why, assignee, and next-step presentation, title-first one-line
  rows grouped by project section, review-mark reconciliation, per-project
  workflow activity decoding and chip freshness, persistent main/deploy
  pipeline failure badges, every-project section plans with Pulls/Actions
  links, the bounded activity poll and ambient refresh schedules, heading
  hierarchy, project lanterns, the collapsible hidden-project list,
  hide-idle filtering, quick facts and the footer version label, and Open PRs
  keyboard-navigation selection and key classification.
- No live-integration suite is currently defined; the retired inferred
  attention and agent-session suites were removed with those features.

## Code-Level Validation

| Layer | Command | PR workflow or check | Required | Notes |
| --- | --- | --- | --- | --- |
| Formatting and static analysis | `make fmt-check vet` | `Go validation` | yes | Go formatting and vet across the module |
| Go behavior | `make test test-race` | `Go validation` | yes | Includes fake GitHub boundaries for the Open PR index |
| CLI build | `make build` | `Go validation` | yes | Builds `bin/hyperlite` |
| Native behavior | `make macos-test` | `macOS validation` | yes | Swift type-check plus executable presentation-model tests |
| Universal app | `make macos-build` | `macOS validation` | yes | Builds and ad-hoc signs both architectures |

## High-Level Suites

| Suite | Type | Environment | Command | Automation | Evidence |
| --- | --- | --- | --- | --- | --- |
| production | end-to-end | production | not applicable | not applicable | Hyperlite is a local desktop application without a deployed production environment |

## Environment Preflights

- The full local gate requires Go, Xcode command-line tools, SwiftUI/AppKit,
  Carbon, `make`, and the checked-in icon source.
- Production validation is `NOT_APPLICABLE`; Hyperlite is packaged locally and
  does not deploy a service.

## Credentials And Test Data

- Code-level suites use fake GitHub boundaries and temporary repositories; they
  record no credentials or authorization material.
- Any future retained test-state cleanup follows `rules/deletion-safety.md`:
  default to a recoverable lifecycle, and require an exact inventory plus
  specific post-outline manual confirmation before hard deletion.

## Evidence And Retention

- `tmp/` is ignored and reserved for future live-run evidence directories.
- CI results remain in GitHub Actions under the repository's configured
  retention policy.
- `tests/RUN_STATUS.md` contains one current row per suite and environment and
  changes only at meaningful validation milestones.

## Automation And Fallbacks

- Pull requests run the complete code-level Go and native macOS gates.

## Known Gaps

- Native view rendering (SwiftUI layout, hover, keyboard monitor wiring) is
  covered by type-checking and pure presentation-model tests, not by automated
  UI tests.
