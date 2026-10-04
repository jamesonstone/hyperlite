---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0040"
  slug: open-pr-project-ignore
  dir: 0040-open-pr-project-ignore
references:
  - id: issue-115
    name: "Per-project ignore toggle in Open PRs"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/115
    relation: implements
    read_policy: must
    used_for: accepted scope
    status: active
skills: []
---

# Open PR Project Ignore

## PURPOSE

Let the operator ignore projects they develop in but whose many open pull
requests belong to another team (for example dewey and aquarium), without
removing them from Hyperlite.

## REQUIREMENTS

- R1: An eye on each project heading toggles ignore; open eye = watched.
- R2: An ignored project shows only its title and is excluded from every
  GitHub request: refresh, probe, activity poll, and workflow catalogs.
- R3: Watching again fetches only that project immediately and expands it.

Orchestration: single-lane, because the config flag, fetch filter, and
heading control form one contract.

## DECISIONS

- Ignore lives in the Hyperlite config (`ignored: true` on the project), not
  in app defaults, because the Go helper owns fetching and must honor it for
  every caller, including the CLI.
- Ignored projects stay configured and projected (title only) instead of
  being removed, so un-ignoring needs no project re-selection; the hide-idle
  list treats them like other projects without rows.
- The immediate fetch uses a per-invocation `--project` limit
  (`Config.RefreshOnly`, never persisted) so watching one project spends quota
  only on it.

## VALIDATION

- Go tests: config round-trip and preservation across selection changes,
  ignored sources never queried and projected as ignored without rows,
  `RefreshOnly` limits the query set.
- Swift tests: ignored decoding (absent key = watched), eye icons, helper
  command mapping, labels.
- `make fmt-check vet test-race build macos-test macos-build` passed.

## REPOSITORY MEMORY

- USER_GUIDE documents the eye and CLI; this spec records the placement
  decision.
