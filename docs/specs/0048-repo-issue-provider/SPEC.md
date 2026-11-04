---
kit_metadata_version: 1
artifact: spec
workflow_version: 3
phase: deliver
delivery_intent: ready_pull_request
feature:
  id: "0048"
  slug: repo-issue-provider
  dir: 0048-repo-issue-provider
references:
  - id: issue-177
    name: Support Linear tickets alongside GitHub issues, per repo .kit.yaml
    type: github-issue
    target: https://github.com/jamesonstone/hyperlite/issues/177
    relation: implements
    read_policy: must
    used_for: accepted scope
    status: active
  - id: open-pr-workflow-activity
    name: Open PR Workflow Activity
    type: specification
    target: docs/specs/0031-open-pr-workflow-activity/SPEC.md
    relation: amends
    read_policy: must
    used_for: the GH-<n> branch and title convention this feature generalizes
    status: active
skills: []
---

# Repository Issue Provider

## PURPOSE

Open PR rows link the ticket a pull request tracks. The link follows that
repository's Kit issue provider, so a Linear repository opens the Linear
ticket and a GitHub-issue repository keeps today's GitHub issue link.

## CONTEXT

Hyperlite derived every tracked issue as `GH-<n>` from the head branch, then
the title, and opened `https://github.com/<owner>/<repo>/issues/<n>`.
`lsmc-bio/labcore` and `lsmc-bio/labcore-ui` now record work in Linear.
A pull request titled `fix(ENG-67): ...` had no issue link.

Kit stores the choice in the repository's `.kit.yaml`:

```yaml
issues:
    provider: linear
    linear:
        workspace: lsmc
        team_id: add0a7c5-383d-4969-98d4-a5402b4cac66
```

An omitted `issues` block or `provider: github` means GitHub Issues. Kit
requires a workspace slug and team UUID before it will write Linear tickets.
`project_id` is optional. Hyperlite does not create tickets. It only needs
the provider and the workspace slug to build a link.

The native window shells out to `hyperlite pull-requests` for each refresh.
That scan already has each configured checkout path. The window paints rows
from the returned JSON and must not read `.kit.yaml` itself.

Orchestration: single-lane. The provider, the key parser, and the row label
share one projection step.

## REQUIREMENTS

- R1: `issues.provider: linear` with a Kit-valid `issues.linear` block selects
  Linear for that checkout. Any other provider, a missing `issues` block, or
  a missing file selects GitHub.
- R2: A Linear row shows the ticket key, for example `ENG-67`, and opens
  `https://linear.app/<workspace>/issue/ENG-67`. The title slug is omitted.
  Linear still resolves that URL.
- R3: A GitHub-issue row keeps the `GH-<n>` label and the GitHub issue URL,
  including the same word-boundary rules as before.
- R4: A missing file, a directory, a file larger than 1 MiB, a read error, or
  YAML that cannot be parsed selects GitHub. An invalid Linear block selects
  GitHub. The scan gains no error and no warning.
- R5: Resolve the provider while projecting a scan, once per checkout that has
  pull requests to label. Reuse a parsed file while its size and modification
  time are unchanged. Do not read the file while painting a row, and do not
  call GitHub to fetch it.
- R6: A provider edit applies on the next projection even when the GitHub
  pull-request cache is reused.
- R7: Tests cover Linear, GitHub, and the missing or unreadable fallback.

Non-goals:

- Creating, querying, or assigning Linear tickets. `team_id` and `project_id`
  are checked so a half-written block does not change links, and are not
  otherwise used.
- Reading `.kit.yaml` from the GitHub default branch.
- Autolinking Linear keys inside the hover-card body. That card still links
  `#123`, `GH-123`, and `owner/repo#123` to GitHub.
- Widening the issue column. `ENG-67` fits the width that already fits
  `GH-1234`. A longer key clips.

## ACCEPTED PLAN

1. Parse the checkout's `.kit.yaml` `issues` block with Kit's provider rules.
2. Stamp `issue_label` and `issue_url` onto open pull requests and undeployed
   pull requests during projection. Leave the pull-request cache unchanged.
3. Prefer those fields in the window. When they are absent, keep recognizing
   `GH-<n>` so an older payload still links.
4. Let Command-P jump to a stamped key (`labcore ENG-67`) as well as `GH-<n>`.

## DECISIONS

- The configured checkout is the source of the file. A refresh already has
  that path, so the provider does not add a GitHub request. Each helper
  process is short-lived. One stat and, when the file changed, one read per
  labeled project is the whole cost.
- Labels are computed at projection rather than stored beside cached GitHub
  rows. `--local` and the five-minute floor still pick up a `.kit.yaml` edit.
- Linear keys are read from the branch first, then a conventional-commit
  scope, then the first standalone token in the title. The team key is two
  to seven letters or digits, starting with a letter. Matching is
  case-insensitive and the label is uppercase, so `eng-67` shows `ENG-67`.
- `GH` is the GitHub convention and is never a Linear team. A short denylist
  (`PR`, `UTF`, `ISO`, `RFC`, `CVE`, `SHA`, `HTTP`, `HTTPS`, `ASCII`, `AES`,
  `RSA`, `TLS`, `SSL`) keeps tokens such as `UTF-8` and `SHA-256` from
  becoming links. A real team with one of those keys would not link.
- When the helper sends no label, the window still applies the `GH-<n>` rule.
  A Linear repository whose title only contains `GH-12` keeps a GitHub link.
  A Linear key found by the helper wins over that fallback.
- The NOT DEPLOYED band shows the same key. Its row still opens the pull
  request, which is how that band already treats `GH-<n>`.
- Command-P learns `ENG-67` because the scan already carries the label. It
  does not re-read `.kit.yaml`.

## DISCOVERIES

- Linear's issue URL is `https://linear.app/<workspace>/issue/<KEY>`. A title
  slug may follow the key and is optional. The older host-only form
  `linear.app/issue/<KEY>` is not the workspace URL this feature builds.
- Kit treats an omitted provider as GitHub and rejects a Linear block whose
  workspace is not a URL slug or whose team id is not a UUID.

## VALIDATION

- `make fmt-check` and `go vet ./...` passed.
- `go test ./internal/issuetrack ./internal/prindex` passed, including
  `-race`. The example prints `ENG-67` and
  `https://linear.app/lsmc/issue/ENG-67`.
- `go test ./...` and `go test -race ./...` failed only
  `internal/discovery.TestInspectCacheReusesUntilGitConfigChanges`
  (`calls=7`). The same failure happens on unmodified `main` in this
  environment. It is not part of this change.
- `make build` passed.
- `make macos-test` was not run. This environment has no Swift toolchain.
  The new Swift cases are in the diff and are part of that command in CI.
- `https://linear.app/lsmc/issue/ENG-67` returns the Linear app shell
  (HTTP 200). The same shell is returned for other `/issue/` paths, so the
  status code does not prove routing. The path matches Linear's documented
  issue URL, with the title slug omitted.

## OUTCOME

- A Linear checkout stamps `ENG-67` and
  `https://linear.app/lsmc/issue/ENG-67` onto open and undeployed pull
  requests. A GitHub checkout still stamps `GH-<n>` and the GitHub issue
  URL. A missing or unreadable `.kit.yaml` stays on GitHub and adds no
  scan warning. The window prefers the stamped link and still recognizes
  `GH-<n>` when the helper sends no label.

## REPOSITORY MEMORY

- This spec records why `.kit.yaml` is read at projection, why invalid
  configuration stays on GitHub without a warning, and which tokens are not
  Linear keys. `docs/USER_GUIDE.md` describes the visible labels.
  `docs/references/testing.md` names the Go coverage.
