---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0046"
  slug: open-pr-row-diffstat
  dir: 0046-open-pr-row-diffstat
references:
  - id: issue-171
    name: Show added and removed line counts left of the Open PR comments icon
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/171
    relation: implements
    read_policy: must
    used_for: accepted scope
    status: active
  - id: open-pr-row-attention
    name: Open PR Row Attention
    type: specification
    target: docs/specs/0042-open-pr-row-attention/SPEC.md
    relation: amends
    read_policy: must
    used_for: trailing cluster order and attention color stay on unresolved work
    status: active
  - id: open-pr-hover-why
    name: Open PR Hover Why
    type: specification
    target: docs/specs/0020-open-pr-hover-why/SPEC.md
    relation: constrains
    read_policy: must
    used_for: hover still omits a dumped diffstat
    status: active
skills: []
---

# Open PR Row Diffstat

## PURPOSE

Show each open pull request's added and removed line counts on the row itself,
immediately left of the comments icon, so change size is visible without
opening GitHub or the hover card.

## CONTEXT

Glance JSON already carries `additions` and `deletions` from the existing
batched GraphQL query. Those counts appear nowhere on the row. Feature 0042
put failed pipeline names and the speech-bubble review-thread count in red
just before the age. Hover (0020) still omits a dumped diffstat.

Orchestration: single-lane. Presentation, accessibility, and the user guide
share one row contract.

## REQUIREMENTS

- R1: Place compact added and removed counts immediately left of the
  speech-bubble review-thread count, after any failed pipeline names, and
  before the age.
- R2: Added counts use theme green. Removed counts use theme red. Unresolved
  work stays red. The diffstat is not attention.
- R3: Reuse glance `additions` and `deletions`. Add no GitHub request.
- R4: Hide the counts when both values are 0. Show only the non-zero side
  when one side is 0.
- R5: VoiceOver names the counts on the row. The hover card does not dump
  them.
- R6: Keep handwritten source and test files at or under 300 lines.

Non-goals:

- Changed-file counts.
- Extra GraphQL fields or round trips.
- Hover-card diffstat.
- Compact `k`/`m` abbreviations.

Observable acceptance:

- A row with additions 12 and deletions 3 shows green `+12` and red `-3`
  immediately left of the comments icon.
- A row with both counts 0 shows no diffstat.
- Hover spoken text still omits `+12`.

## ACCEPTED PLAN

1. Add a presentation helper for visibility, `+N`/`-N` text, and spoken
   labels from glance counts.
2. Render that helper in the trailing cluster, with green and red applied
   per side, after failed pipelines and before the comments icon.
3. Append the spoken label to the row accessibility string only.
4. Cover the helper and row spoken text with Swift tests. Update the user
   guide.

## DECISIONS

- Reuse glance fields. A new query would buy nothing and would spend quota.
- Keep the counts informational. Wrapping them in the 0042 red cluster color
  would make additions look like failures.
- Hide a zero side. `+0` or `-0` adds width without information.
- Keep hover free of the counts. The row now carries them; dumping them on
  hover would repeat dense metadata that 0020 already rejected.
- Use raw integers with a leading `+` or `-`. No thousands separators and no
  `k`/`m` suffixes.

## DISCOVERIES

- `internal/prindex` already requests `additions deletions changedFiles`.
  Swift already decodes them onto `HyperlitePullRequestGlance`.

## VALIDATION

- `make macos-test` passed. New Swift tests cover zero-hide, per-side
  format, row spoken text, and hover still omitting the counts.
- `env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 make
  fmt-check vet test test-race build` passed. The first `make test` run
  failed `TestInspectCacheReusesUntilGitConfigChanges` because this shell
  exports `GIT_CONFIG_COUNT=1`; that path is unrelated and CI does not set
  those variables.
- `make macos-build` passed and wrote `build/Hyperlite.app`.

## OUTCOME

- Open PR rows show green `+N` and red `-N` immediately left of the
  comments icon from glance `additions` and `deletions`. Zero sides stay
  hidden. Hover still omits a dumped diffstat. No extra GitHub request.

## REPOSITORY MEMORY

- This spec records placement, color, visibility, and the no-extra-fetch
  choice. `docs/USER_GUIDE.md` describes the visible cluster.
  `docs/references/testing.md` names the new presentation tests.
