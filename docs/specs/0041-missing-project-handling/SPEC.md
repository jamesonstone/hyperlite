---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0041"
  slug: missing-project-handling
  dir: 0041-missing-project-handling
references:
  - id: issue-119
    name: "Handle configured projects whose GitHub repository or local directory is gone"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/119
    relation: implements
    read_policy: must
    used_for: accepted scope
    status: active
  - id: deletion-safety
    name: Deletion Safety
    type: ruleset
    target: docs/references/rules/deletion-safety.md
    relation: constrains
    read_policy: must
    used_for: soft-delete and restore contract for retired projects
    status: active
skills: []
---

# Missing Project Handling

## PURPOSE

Stop showing raw errors for projects that no longer exist: retire projects
whose directory is gone, and tell the operator what to do when only the GitHub
repository is gone.

## CONTEXT

`jamesonstone/sigint` and `jamesonstone/tminus-reset` have local directories
but deleted remotes, so every refresh showed GitHub's raw "Could not resolve to
a Repository" error. Investigation found a worse latent bug: `config.Load`
failed outright when any configured project directory was missing, and
`config.Mutate` treated that wrapped `ErrNotExist` as "no config file yet",
so the next project add or remove would rewrite an almost empty configuration.

Orchestration: single-lane, because config loading, retirement, and the
scan wiring share one contract.

## REQUIREMENTS

- R1: A configured project whose directory disappeared never breaks loading
  and stops being scanned, recoverably.
- R2: A project whose GitHub repository no longer resolves, with its directory
  present, shows an actionable message naming the directory.
- R3: No configuration write may treat a missing project directory as a
  missing configuration file.

## ACCEPTED PLAN

1. Load missing project directories into `MissingProjects` instead of failing.
2. Fix `Mutate` to decide a missing config from the config file itself.
3. Retire missing projects during stale and forced refreshes and report them;
   add `projects restore`.
4. Rewrite GitHub's missing-repository error per project.

## DECISIONS

- Retirement is a soft delete (deletion-safety rule): the entry moves to
  `retired_projects` with path, reason, and time, is never scanned, and is
  restorable with `hyperlite projects restore <path>` or by adding it back.
- Retirement runs on stale and forced refreshes; `--local` and `--activity`
  stay read-only.
- Missing project directories load into `MissingProjects` and are written back
  unchanged by other config mutations until retired.
- `Mutate` decides "no config yet" from the config file itself.
- A GitHub-missing repository with a present directory keeps its project and
  gets an actionable message; the directory may hold unpushed work, so
  Hyperlite never deletes or retires it automatically.

## DISCOVERIES

- The latent config-wipe path described under CONTEXT was found while tracing
  why a missing directory would error; it is now covered by a regression test.

## VALIDATION

- Go tests: missing directories load and never wipe the config (regression),
  retire and restore round-trip, the CLI retires and warns during a refresh,
  and the missing-repository message.
- Live: both dead repositories show the new message; the operator's config was
  unchanged because every directory exists.
- `make fmt-check vet test-race build` passed.

## OUTCOME

- Vanished projects retire with a restorable record; deleted repositories show
  what to delete; the configuration can no longer be wiped by a missing
  project directory.

## REPOSITORY MEMORY

- CONSTITUTION records the never-silently-drop and config-write invariants;
  USER_GUIDE documents retirement and restore.
