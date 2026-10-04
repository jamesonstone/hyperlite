---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0042"
  slug: open-pr-row-attention
  dir: 0042-open-pr-row-attention
references:
  - id: issue-125
    name: "Show review feedback and failed pipelines in red beside each Open PR's age"
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/125
    relation: implements
    read_policy: must
    used_for: accepted scope
    status: active
skills: []
---

# Open PR Row Attention

## PURPOSE

Show what blocks each pull request where the eye ends a row: failed pipelines
by short name and unresolved review feedback, in red beside the age, so a
known-harmless failure (labcore's docs check) is judged without opening GitHub.

Orchestration: single-lane; the fetch extension and row presentation share
one contract.

## DECISIONS

- Failed pipeline names reuse the existing per-head check-suite follow-up,
  now issued for failing as well as pending heads (still capped at ten heads
  per repository). Green heads cost nothing; a full 102-repository refresh
  added 3 GraphQL points.
- Only the newest run per workflow file on the exact head counts, so a green
  rerun clears the warning.
- Short names drop filler words (check, workflow, pipeline, job), keep the
  first word unless it is under three characters, fall back to the file stem,
  and cap at twelve characters. Full names stay in tooltips and the hover card.
- A failing rollup with no failed Actions run shows `checks` so non-Actions
  failures are never hidden.
- Heading chips ignore finished pull-request runs: a PR's failed CI describes
  that PR, not the project.

## VALIDATION

- Go test: failing and pending heads get the run follow-up; green heads do not.
- Swift tests: short-name rules, newest-run-per-head selection, rerun
  clearing, non-Actions fallback.
- Live: bloom #16-18 and labcore-ui #813/#822 show `CI`; dayhoff #157 (no
  Actions run) shows `checks`.

## REPOSITORY MEMORY

- USER_GUIDE documents the red cluster; this spec records the data and naming
  decisions.
