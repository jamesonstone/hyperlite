# Testing Reference

## Purpose

- Record the project's durable commands, suites, environments, automation, and evidence expectations
- Follow `rules/testing-and-environment-validation.md` for the mandatory cross-project testing and production-safety contract
- Keep feature-specific testing details in the current feature's `SPEC.md` VALIDATION and OUTCOME sections; legacy staged flows may still use `PLAN.md` or `TASKS.md`

## Current State

- Go package tests cover deterministic scanner, correlation, state, inference,
  CLI, git maintenance, and failure behavior.
- Swift executable model tests and native type-checking cover schema and
  presentation behavior.
- Go contract and integration tests cover the remaining CLI agent-session
  authority, provider registry, exact actions, configuration safety, private
  socket, Codex stdio protocol, discovery-only `notLoaded` rollout fallback,
  incremental cursors, current-date discovery, replacement recovery, adaptive
  child ownership, exact process proof, action queues, health/self-test,
  coalescing, resolved-input transitions, pre-store expiry, and redaction.
- Swift executable tests cover Command-K without unused workspace actions,
  helper PATH including `~/.local/bin`, default-branch update summaries, Open
  PRs merge-conflict decoding, hide-drafts filtering, conflict-column layout
  reservation, Copy Open PR Merge Prompt labels, Command-K Theme and Font Size
  nested lists, Open PR hover glance fields, pin/reorder presentation, and
  Command-K literal search without loading sentence embeddings. The native
  window no longer compiles Agent Island, Agent Tasks, Pinboard, or pinned Codex
  presentation tests.
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
| agent sessions bridge | live-integration | local | `tests/live-integration/local/agent-session-bridge-live.sh` | manual milestone | `tmp/<UTC-date>/agent-session-bridge-live.sh/<run-number>/` |
| agent session cross-process discovery | live-integration | local | isolated `hyperlite-cli agent sessions serve` with a metadata-only JSON projection | manual milestone | `tmp/<UTC-date>/agent-session-discovery-live/<run-number>/` |
| agent session resources | live-integration | local | `tests/live-integration/local/agent-session-resource-live.sh` | manual release gate | `tmp/<UTC-date>/agent-session-resource-live.sh/<run-number>/result.json` |
| agent sessions provider/display matrix | live-integration | local | manual acceptance matrix | manual milestone | provider and physical-display evidence pending |
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
- Resource acceptance additionally requires `lsof`, `ps`, and `jq`. The
  resource suite defaults to a 30-minute post-warmup sample. Set
  `HYPERLITE_RESOURCE_SOAK_SECONDS=28800` for the required eight-hour soak and
  `HYPERLITE_APP_PID` to include the packaged app in combined CPU sampling.

## Credentials And Test Data

- The live scan uses the operator's existing `gh` authentication and never
  records credentials or authorization material.
- Repository, GitHub, provider, and application live operations remain
  read-only. The resource suite creates only metadata-only sessions, rollout
  files, and a private socket beneath one task-owned temporary home, then
  verifies owner-EOF cleanup and removes that exact directory. It creates no
  provider, infrastructure, or durable application record and requires no
  cleanup credential, rate budget, or cost budget.
- Any future retained test-state cleanup follows `rules/deletion-safety.md`:
  default to a recoverable lifecycle, and require an exact inventory plus
  specific post-outline manual confirmation before hard deletion.

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
- Agent sessions are enabled by default, but full provider-parity evidence
  remains partial until every frozen provider passes a real local lifecycle
  smoke, action-capable providers pass one bounded response round trip, and
  both physical-notch and external/notchless display journeys pass.
  Deterministic fixtures do not replace that residual acceptance evidence.
- Issue #49 live regression evidence proves current external idle transparency
  and cross-process Codex discovery. Direct pointer-only hover remains a
  deterministic policy assertion because the local Computer Use API exposes
  clicks and drags rather than pointer-only motion.
- Feature 0012's short resource smoke proves the harness and bounded synthetic
  load, not the mandatory 30-minute combined-app sample or eight-hour soak;
  those remain `PARTIAL` until their full wall-clock observations complete.
