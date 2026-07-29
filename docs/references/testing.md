# Testing Reference

## Purpose

- Record durable repo-wide testing guidance that is broader than one feature
- Keep feature-specific testing details in the current feature's `SPEC.md` VALIDATION and OUTCOME sections; legacy staged flows may still use `PLAN.md` or `TASKS.md`

## Current State

- Go package tests cover deterministic scanner, correlation, state, inference,
  CLI, and failure behavior.
- Swift executable model tests and native type-checking cover schema and
  presentation behavior.
- A read-only local live-integration suite validates recovery of the selected
  R2 and Event Sink goal threads against current repository and GitHub
  evidence.

## Code-Level Validation

| Layer | Command | PR workflow or check | Required | Notes |
| --- | --- | --- | --- | --- |
| Formatting and static analysis | `make fmt-check vet` | `Go validation` | yes | Go formatting and vet across the module |
| Go behavior | `make test test-race` | `Go validation` | yes | Includes fake GitHub/Ollama boundaries and golden R2/Event Sink fixtures |
| CLI build | `make build` | `Go validation` | yes | Builds `bin/hyperlite` |
| Native behavior | `make macos-test` | `macOS validation` | yes | Swift type-check plus executable presentation-model tests |
| Universal app | `make macos-build` | `macOS validation` | yes | Builds and ad-hoc signs both architectures |

## High-Level Suites

| Suite | Type | Environment | Command | Automation | Evidence |
| --- | --- | --- | --- | --- | --- |
| inferred attention recovery | live-integration | local | `tests/live-integration/local/inferred-attention-live-scan.sh <r2-path> <event-sink-path>` | manual milestone | `tmp/<UTC-date>/inferred-attention-live-scan.sh/<run-number>/` |
| production | end-to-end | production | not applicable | not applicable | Hyperlite is a local desktop application without a deployed production environment |

## Environment Preflights

- The full local gate requires Go, Xcode command-line tools, SwiftUI/AppKit,
  Carbon, `make`, and the checked-in icon source.
- The live scan requires readable local R2 and Event Sink Git repositories,
  authenticated read access through `gh`, `jq`, and no repository mutation.
- Ollama is optional. Contract behavior uses a fake server in Go tests; live
  semantic enrichment runs only when `settings.ollama_model` is configured.
- Production validation is `NOT_APPLICABLE`; Hyperlite is packaged locally and
  does not deploy a service.

## Credentials And Test Data

- The live scan uses the operator's existing `gh` authentication and never
  records credentials or authorization material.
- All live operations are read-only. No synthetic records, infrastructure,
  cleanup credentials, rate budget, or cost budget are required.

## Evidence And Retention

- `tmp/` is ignored. Each live run atomically reserves its own directory and
  records redacted `output.txt`, `scan.json`, state, and `result.json`.
- CI results remain in GitHub Actions under the repository's configured
  retention policy.
- `tests/RUN_STATUS.md` contains one current row per suite and environment and
  changes only at meaningful validation milestones.

## Automation And Fallbacks

- Pull requests run the complete code-level Go and native macOS gates.
- Live recovery remains a manual milestone because it depends on the
  operator's selected repositories, worktrees, GitHub identity, and current
  remote evidence. Deterministic golden fixtures cover the same structural
  acceptance contract in pull-request CI.

## Known Gaps

- A live Ollama response is unobserved when no model is configured; fake-server
  contract tests prove cited-schema validation and deterministic fallback.
- The local live scan proves current read-only evidence recovery, not deployed
  operational state in the referenced projects.
