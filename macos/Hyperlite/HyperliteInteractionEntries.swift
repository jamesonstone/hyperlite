import Foundation

extension HyperliteInteractionModel {
    static func commandEntries(
        threads: [HyperliteThread],
        agentIslandEnabled: Bool,
        visibleOpenPullRequestCount: Int = 0,
        mergePromptCopied: Bool = false
    ) -> [HyperlitePaletteEntry] {
        var entries = [
            actionEntry(
                "action:show-dashboard", "Show Dashboard", "Switch to Dashboard · ⌘1",
                "rectangle.grid.1x2", .showDashboard
            ),
            actionEntry(
                "action:show-pinboard", "Show Pinboard", "Switch to Pinboard · ⌘2",
                "rectangle.3.group", .showPinboard
            ),
            actionEntry(
                "action:add-pinboard-note", "Add Pinboard Note",
                "Create a private spatial note", "note.text.badge.plus", .addPinboardNote
            ),
            actionEntry(
                "action:add-pinboard-section", "Add Pinboard Section",
                "Create a bounded spatial region", "rectangle.badge.plus", .addPinboardSection
            ),
            actionEntry(
                "action:open-pinboard-archive", "Open Pinboard Archive",
                "Restore archived private notes", "archivebox", .openPinboardArchive
            ),
            actionEntry(
                "action:refresh", "Refresh",
                "Refresh projects, open pull requests, and pinned Codex threads",
                "arrow.clockwise", .refresh
            ),
            actionEntry(
                "action:force-cache-refresh", "Force Cache Refresh",
                "Retry GitHub data and replace cached errors",
                "arrow.triangle.2.circlepath", .forceCacheRefresh
            ),
            actionEntry(
                "action:copy-open-pr-merge-prompt",
                HyperliteOpenPRMergePrompt.commandTitle(copied: mergePromptCopied),
                HyperliteOpenPRMergePrompt.commandSubtitle(
                    visibleCount: visibleOpenPullRequestCount,
                    copied: mergePromptCopied
                ),
                HyperliteOpenPRMergePrompt.commandSymbol(copied: mergePromptCopied),
                .copyOpenPRMergePrompt
            ),
            actionEntry(
                "action:add-project", "Add Project", "Choose a Git repository to configure",
                "folder.badge.plus", .addProject
            ),
            actionEntry(
                "action:remove-project", "Remove Project",
                "Choose a configured project to remove",
                "folder.badge.minus", .chooseProjectToRemove
            ),
            actionEntry(
                "action:settings", "Settings", "Open Hyperlite settings",
                "gearshape.fill", .settings
            ),
        ]
        if HyperliteFeatureFlags.agentSessionPresentation {
            entries.insert(actionEntry(
                "action:show-sessions", "Show Agent Tasks", "Switch to Agent Tasks · ⌘3",
                "terminal.fill", .showSessions
            ), at: 2)
            entries.insert(actionEntry(
                "action:toggle-agent-island",
                agentIslandEnabled ? "Turn Agent Island Off" : "Turn Agent Island On",
                agentIslandEnabled
                    ? "Hide the floating island; Agent Tasks keeps tracking"
                    : "Show live agent status at the Mac notch or top edge",
                "rectangle.topthird.inset.filled",
                .toggleAgentIsland
            ), at: 3)
        }
        entries.append(contentsOf: threads.map { thread in
            actionEntry(
                "thread:\(thread.id)",
                hoverTitle(for: thread),
                hoverSummary(for: thread),
                thread.phase.symbol,
                .reveal(thread.id)
            )
        })
        return entries
    }

    static func projectSummary(pullRequestCount: Int, laneCount: Int) -> String {
        "\(pullRequestCount) PR\(pullRequestCount == 1 ? "" : "s") · " +
            "\(laneCount) lane\(laneCount == 1 ? "" : "s")"
    }

    static func actionEntry(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ action: HyperlitePaletteAction
    ) -> HyperlitePaletteEntry {
        HyperlitePaletteEntry(
            id: id, title: title, subtitle: subtitle, symbol: symbol, kind: .action(action)
        )
    }
}
