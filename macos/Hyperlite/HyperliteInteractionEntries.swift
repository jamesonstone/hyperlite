import Foundation

extension HyperliteInteractionModel {
    static func commandEntries(
        visibleOpenPullRequestCount: Int = 0,
        mergePromptCopied: Bool = false
    ) -> [HyperlitePaletteEntry] {
        [
            actionEntry(
                "action:theme", "Theme",
                "Choose a light or dark application theme",
                "paintpalette", .showThemes
            ),
            actionEntry(
                "action:font-size", "Font Size",
                "Choose 12 pt or 10 pt list type",
                "textformat.size", .showFontSizes
            ),
            actionEntry(
                "action:refresh", "Refresh",
                "Refresh open pull requests and the daily note date",
                "arrow.clockwise", .refresh
            ),
            actionEntry(
                "action:force-cache-refresh", "Force Cache Refresh",
                "Retry GitHub data and replace cached errors",
                "arrow.triangle.2.circlepath", .forceCacheRefresh
            ),
            actionEntry(
                "action:update-default-branches", "Update Default Branches",
                "Fast-forward each configured default branch when Git allows",
                "arrow.down.circle", .updateDefaultBranches
            ),
            actionEntry(
                "action:sweep-worktrees", "Sweep Worktrees",
                "Open interactive git wt sweep in Terminal",
                "trash", .sweepWorktrees
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
    }

    static func themeEntries(currentID: String) -> [HyperlitePaletteEntry] {
        HyperliteThemeCatalog.all.map { theme in
            let current = theme.id == currentID
            return HyperlitePaletteEntry(
                id: "theme:\(theme.id)",
                title: theme.title,
                subtitle: current ? "Current" : (theme.isLight ? "Light" : "Dark"),
                symbol: current ? "checkmark" : (theme.isLight ? "sun.max" : "moon"),
                kind: .action(.setTheme(theme.id))
            )
        }
    }

    static func fontSizeEntries(current: HyperliteFontSize) -> [HyperlitePaletteEntry] {
        HyperliteFontSize.allCases.map { size in
            let selected = size == current
            return HyperlitePaletteEntry(
                id: "font-size:\(size.rawValue)",
                title: size.title,
                subtitle: selected ? "Current · \(size.subtitle)" : size.subtitle,
                symbol: selected ? "checkmark" : "textformat.size",
                kind: .action(.setFontSize(size))
            )
        }
    }

    static func projectSummary(pullRequestCount: Int, laneCount: Int) -> String {
        let pullRequests = "\(pullRequestCount) PR\(pullRequestCount == 1 ? "" : "s")"
        guard laneCount > 0 else { return pullRequests }
        return pullRequests + " · \(laneCount) lane\(laneCount == 1 ? "" : "s")"
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
