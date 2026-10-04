# User guide

Hyperlite is a native macOS window plus a CLI that watch open pull requests
across your configured projects. This guide covers its user-facing behavior
and local data boundaries.

## Launch and configuration

```sh
make hyper
```

This builds `build/Hyperlite.app`, stops a prior running Hyperlite process, and
opens the fresh windowed app.

The first default run copies `~/.config/beacon/config.yaml` directly to
`~/.config/hyperlite/config.yaml` when Hyperlite does not already own a config.
Later runs use only the Hyperlite copy. Select projects with
`hyperlite projects`, or add and remove them with `hyperlite projects add` and
`hyperlite projects remove`.

## Native workspace

The native app is one window, and the Open PRs list fills it. Launch always
opens that window; it does not start a menu bar extra or any other surface.
The window title is `👻 hyperlite`. GitHub GraphQL quota, Sweep Worktrees, a
subtly orange Refresh action, and Settings sit in a row above the list. The
default Control+Shift+H hotkey brings the window forward; becoming active
still refreshes stale Open PRs, but the hotkey itself does not force GitHub
work. Command-P, Remove Project, and Settings load the configured project list
when opened, not at launch. Theme and Font Size live only in Command-K; they
are not in Settings.

Configured repositories determine which Open PRs appear. Add or remove them
from Settings, Command-K, or the CLI. Command-P is a cheap lookup of those
repositories and their loaded pull requests; it is not a dashboard map.

Earlier releases also offered notes, a pinboard, agent sessions, inferred
attention threads, pinned and reordered Open PR rows, and a default-branch
fast-forward action. Those features are retired. Files they wrote under
`~/.local/share/hyperlite` and `~/.local/state/hyperlite` are left on disk
untouched; Hyperlite no longer reads or writes them.

### GitHub quota

Existing GraphQL requests also return the caller's quota metadata, so the
header indicator adds no request or `gh` process. It shows calls used out of
the limit. Hover exposes remaining capacity, local reset and observation times,
and the last query's cost and node count; clicking pins the same details until
another click or native dismissal.

Only complete observations replace the separately cached quota snapshot.
Healthy capacity stays quiet, 20 percent remaining warns in orange, and 10
percent remaining is critical in red. The same cached observation and burn
rate gate the automatic workflow-activity poll; the governor can only deny
that poll, never add requests. Once two valid observations exist in the
same reset window, the popover shows the trailing quota-point burn rate, sample
duration, projected depletion time, and whether depletion falls before or
after reset. Reset crossings, counter decreases, and samples shorter than one
minute remain explicitly measuring rather than projecting.

### Open pull requests

The Open PRs list has no visible scroll bar; scroll with the trackpad or wheel,
or move through it with `j`/`k` and the arrow keys.

Open PRs load from a separate private cache. Hyperlite keeps the list current
on its own: while the window is visible it checks once a minute, and revealing
the window, foreground activation, or waking the Mac checks immediately. Each
configured repository is re-queried no more often than every five minutes.
The helper remembers each repository's resolved remote and base branch and
reuses them while the repository's git configuration and refs are unchanged,
so refreshes and the running-workflow poll start without spawning git, and
running-workflow timers pause while the window is hidden.
Automatic refreshes reuse cached pull-request details for up to fifteen minutes
when the probe shows a repository's open count and newest update unchanged and
no check is pending, so an idle watch list costs only the probe (about one
GraphQL point per ten repositories). They pause entirely while fewer than the
larger of 1,000 points or twenty percent of the hourly quota remain, and the
Open PRs warning says until when; Refresh always fetches everything.
A refresh first probes repositories cheaply in batches of ten for their open
pull-request count and workflow activity, then reads full pull-request details
one repository per query, concurrently, only where pull requests are open. One
slow, missing, or failing repository therefore never hides another's rows.
Refresh forces the index current; Force Cache Refresh in Command-K retries only
this cache without refreshing unrelated projections. While a fetch is in
flight, a small spinner sits beside the quick facts; cached rows stay on
screen.

The top bar shows quick facts in priority order, as many as fit the window:
open pull requests, projects with open pull requests, failing CI, pull
requests needing review feedback, merge conflicts, pull requests older than 10
and 30 days, ready and draft counts, updated today, bot pull requests, running
projects, hidden projects with a failing pipeline, ignored projects, and the
oldest pull request's age. Hover a fact for its definition. The footer shows
when Open PRs were last updated (left) and the Hyperlite version and commit
(right). While you scroll, the current project's heading stays pinned at the
top until the next project's heading replaces it.
The packaged app preserves its inherited executable search path and adds the
standard Apple Silicon and Intel Homebrew directories plus `~/.local/bin` so
Finder launches can resolve `gh` and `git-wt`.

Failed checks retain visibly cached rows. A project with no usable GitHub
identity or cache is shown as unavailable. Pagination fails safely on a
repeated cursor or bounded page limit instead of risking an unbounded GitHub
query loop.

Every configured project has its own section, even with no open pull
requests. Projects with open pull requests come first, ordered by their most
recently updated pull request; projects without rows follow in configuration
order. The section header carries the repository name, its row count, a strip
of the project's workflows, and two small buttons that open the repository's
Pulls and Actions pages on GitHub. Clicking the repository name opens the
repository itself. A project with nothing open collapses to one quiet heading
that folds in `no open pull requests`; cached or unavailable projects show
their availability text there instead.

Projects without an open pull request are hidden by default; the eye control
in the top bar shows or hides them. Hiding keeps only projects with an open
pull request in the list — a no-PR project is hidden even when a workflow is
running or failing; the `hidden failing` quick fact counts hidden projects
with a failing pipeline. Showing all projects (eye off) lists them inline with
their availability text, workflow chips, pipeline-alert badges, and
Pulls/Actions links. The hide-idle eye stays
quiet while idle projects are hidden and brightens only when they are shown.
Hovering it while projects are hidden lists every hidden project by name
(ignored ones are marked), scrolling when the list is long.

The open count leads the top bar in larger type. Headings for
projects with open PRs use primary semibold type; idle headings drop to
compact muted type so they recede. A no-PR project with a running or failing
workflow stays one line in secondary text. Repository names, workflow chips,
and pull-request text share one left edge past the review checkbox. Each
visible project is marked by a thin left lantern instead of a filled card;
running work lights that lantern cyan, and a cached main/deploy pipeline
failure lights it orange. Workflow chips sit on the heading row after the
repository name. Failed default-branch **main**/**ci** or **deploy** pipelines
keep a persistent orange **main** or **deploy** badge on that heading until the
next matching run is green; those badges reuse the already-fetched Actions
cache and do not add GitHub calls. Projects with open pull requests can be
collapsed with the chevron at the left of the heading. Collapsed, a project
keeps its name and open-PR count; the collapse state persists per project.

Each project heading also has its own eye. Closing it ignores the project: the
section shrinks to its name plus `ignored`, and Hyperlite stops every GitHub
request for it (refreshes, probes, and the workflow poll). Use it for
repositories you work in but whose pull requests belong to another team.
Opening the eye again fetches that one project immediately and expands its
section. The same switch is `hyperlite projects ignore <path>` and
`hyperlite projects watch <path>`; the choice is stored as `ignored: true` on
the project in the Hyperlite config.

When a configured project's local directory disappears, the next refresh
moves it to `retired_projects` in the config (with the reason and time) and
the Open PRs warnings name it; it is no longer scanned. Restore it with
`hyperlite projects restore <path>` once the directory exists again, or by
adding the project back. When GitHub reports that a project's repository no
longer exists but the local directory is still there, its heading says so and
names the directory to delete.

The workflow strip sits on the repository heading row. It lists every file
under `.github/workflows` on the default
branch, named by the file's `name:` key, plus any observed dynamic workflow
such as CodeQL. A workflow or environment deployment that GitHub reported
running within the last two minutes becomes a cyan chip with a still cyan dot
and the elapsed run time. Older active data shows a quiet `last seen HH:mm`
instead.
Finished workflows show a green, red, or muted dot. Hovering a chip shows the
run status, trigger, deployment environment, and links to the run and
deployment log.

While a scan reports running work, Hyperlite polls that activity about once a
minute with one small GraphQL query for only the affected repositories. The
poll runs only while the window is visible on screen (it may sit beside your
editor), stops after thirty minutes, and defers to the quota governor: it
needs at least the larger
of 1,000 points or thirty percent of the limit remaining, a projected twenty
percent left at reset, and at most sixty polls per quota window. Refresh and
Force Cache Refresh cancel the loop and fetch pull requests early.

While a scan reports running work, Hyperlite polls that activity about once a
minute with one small GraphQL query for only the affected repositories. The
poll runs only while the window is visible on screen (it may sit beside your
editor), stops after thirty minutes, and defers to the quota governor: it
needs at least the larger
of 1,000 points or thirty percent of the limit remaining, a projected twenty
percent left at reset, and at most sixty polls per quota window. Refresh and
Force Cache Refresh cancel the loop and fetch pull requests early.

Each row is one line: numbers, a compact ready/draft badge, optional
merge-conflict icon, the title, unresolved work in red, and its age. Number
and ready/draft stay whole words; a long title truncates instead of wrapping.
Rows sit under their repository heading, so the project name is not repeated
on every line. Each row leads with two labeled numbers: `PR #<n>` opens the
pull request, and `GH-<n>` opens the issue it tracks when its branch or title
names one through the `GH-<n>` convention (the column stays blank otherwise).
The title also opens the pull request. The conflict column stays aligned
when there is no confirmed conflict;
`MERGEABLE`, `UNKNOWN`, and older cache entries without the field stay blank.
VoiceOver names confirmed conflicts only and omits unconfirmed `MERGEABLE`,
`UNKNOWN`, and legacy rows. Unresolved work sits in red just before the age:
each failed GitHub Actions pipeline on the current head by a short name (for
example `✕ docs`, so a docs-check failure you can judge harmless is visible
without opening the repository; hover shows the full name), `✕ checks` when a
non-Actions check failed, then a speech-bubble count of unresolved,
non-outdated review threads (CodeRabbit or human feedback). Clean rows show
nothing there. Failed pipeline names come from one small follow-up query for
failing heads only; green pull requests cost nothing extra, and a failed pull
request run never turns the project heading red. The row content opens the pull
request; its separate leading checkbox, immediately before the row text,
changes only the private `Reviewed by me` marker, and an empty checkbox stays
quiet until the row is hovered. Hovering a row shows
a glance card after about 1.35 seconds of steady hover, with compact
identity, the title, who is assigned or `unassigned`, a summary of up to about
600 characters drawn from the pull request description, and one next step
such as fix merge conflicts, failing CI, unresolved review threads, or
waiting on review. Hover does not dump author, diffstat, SHA, or URL, and it
does not call GitHub.

A review mark is stored locally for the exact observed head commit and survives
relaunches. Marked rows stay in place and become subtly muted. When current
GitHub evidence reports a new head commit, Hyperlite restores normal emphasis
and shows an orange stale marker until the new revision is reviewed or the mark
is cleared. Cached or unavailable evidence preserves the last mark; a cached
row may clear that mark but cannot create or replace one.

Copy Open PR Merge Prompt remains in Command-K. Copy writes a durable
instruction plus each visible pull request's identity, URL, draft/ready
state, confirmed merge-conflict hint or `merge conflicts not confirmed`,
and unresolved review-thread count to the clipboard, then confirms for two
seconds. It does not call `gh`, open GitHub, or mutate pull requests. An
empty visible list leaves the clipboard unchanged.

Command-K Theme opens a nested list of eleven families with light and dark
variants; the current theme is marked. Command-K Font Size chooses 12 pt
(default) or 10 pt list type. Both persist locally.

`Reviewed by me` is organization metadata, not GitHub approval, review-feedback
resolution, passing checks, mergeability, or permission to merge. Hyperlite
does not post a comment, label, or review. A merge operator or coding agent must
still refresh and verify the exact head, feedback, checks, conflicts, protection
rules, and final merged state.

### Sweep Worktrees

Sweep Worktrees opens Terminal running interactive `git wt sweep`. Hyperlite
does not pass `--auto` and does not delete worktrees itself; confirmation stays
in `git-wt`.

### Keyboard shortcuts

- Whenever no palette or text field is focused, `j`/`k` and the `Down`/`Up`
  arrows move a highlighted selection between project headings and
  pull-request rows. `Return` opens the selected pull request or repository.
  The highlight appears only after the first navigation key, and the list
  scrolls to keep the selection centered, so the keyboard is the fastest way
  through Open PRs.
- `Command+R` refreshes Open PRs and the configured project list.
- `Command+K` opens a searchable command palette with Theme, Font Size,
  Refresh, Force Cache Refresh, Sweep Worktrees, Copy Open PR Merge Prompt,
  Add Project, Remove Project, and Settings.
  Force Cache Refresh retries every configured GitHub repository regardless of
  cache age so a successful check replaces stale cached errors. Copy Open PR
  Merge Prompt copies the merge-ready prompt for the currently visible rows and
  stays open to confirm the copy.
- `Command+P` opens the same searchable surface in configured-project mode.
  Projects start collapsed and expand to show loaded open pull requests and
  local worktrees. Type a project and a number to jump straight to a pull
  request: `kahlo 33`, `kahlo #33`, or `kahlo GH-33` lists the pull request
  numbered 33 and any pull request tracking issue 33, each labeled with which
  number matched. Choosing one closes the palette, expands its project, scrolls
  the row to the middle of the list, and highlights it; `Return` then opens it
  on GitHub.

Add Project is also available from Settings. Project selection changes are
written atomically by the bundled helper. Hyperlite does not expose
worktree-pruning functionality.

## CLI reference

Running `hyperlite` with no subcommand prints help.

```sh
hyperlite pull-requests [--json]
hyperlite pull-requests --json --local
hyperlite pull-requests --json --force
hyperlite pull-requests --json --activity
hyperlite projects
hyperlite projects list [--json]
hyperlite projects add /path/to/repository
hyperlite projects remove /path/to/repository
hyperlite version
```

## Local data

The project pull-request cache is stored with user-only permissions at
`$XDG_STATE_HOME/hyperlite/pull-requests.json`, or
`~/.local/state/hyperlite/pull-requests.json` by default. Review marks, project
collapse state, the hide-idle choice, theme, and font size are stored in the
application's user defaults.
