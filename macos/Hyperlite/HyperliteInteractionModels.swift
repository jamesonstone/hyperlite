import Foundation

enum HyperliteWorkspaceSizing {
    static let sectionSpacing: CGFloat = 14
    static let sectionCount: CGFloat = 3
    static let minimumNotepadEditorHeight: CGFloat = 44

    static func sectionHeight(availableHeight: CGFloat) -> CGFloat {
        max(0, availableHeight - sectionSpacing * (sectionCount - 1)) / sectionCount
    }
}

enum HyperlitePaletteMode: String, Hashable, Identifiable {
    case commands
    case projects
    case removeProjects

    var id: String { rawValue }
}

enum HyperlitePaletteAction: Equatable {
    case refresh
    case forceCacheRefresh
    case settings
    case addProject
    case chooseProjectToRemove
    case removeProject(String)
    case reveal(String)
    case openPullRequest(String)
    case revealPath(String)
    case focusPinnedNote
    case openDailyNote(String)
}

struct HyperlitePaletteEntry: Equatable, Identifiable {
    enum Kind: Equatable {
        case action(HyperlitePaletteAction)
        case project(String)
    }

    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let kind: Kind
    let parentProjectID: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        kind: Kind,
        parentProjectID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.kind = kind
        self.parentProjectID = parentProjectID
    }
}

enum HyperliteInteractionModel {
    static func commandEntries(threads: [HyperliteThread]) -> [HyperlitePaletteEntry] {
        var entries = [
            actionEntry(
                "action:refresh", "Refresh", "Refresh projects, open pull requests, and pinned Codex threads",
                "arrow.clockwise", .refresh
            ),
            actionEntry(
                "action:force-cache-refresh", "Force Cache Refresh",
                "Retry GitHub data and replace cached errors",
                "arrow.triangle.2.circlepath", .forceCacheRefresh
            ),
            actionEntry(
                "action:add-project", "Add Project", "Choose a Git repository to configure",
                "folder.badge.plus", .addProject
            ),
            actionEntry(
                "action:remove-project", "Remove Project", "Choose a configured project to remove",
                "folder.badge.minus", .chooseProjectToRemove
            ),
            actionEntry(
                "action:settings", "Settings", "Open Hyperlite settings",
                "gearshape.fill", .settings
            ),
        ]
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

    static func projectEntries(
        projects: [HyperliteProjectLocation],
        pullRequests scan: HyperliteProjectPullRequestScan?,
        expandedProjects: Set<String>
    ) -> [HyperlitePaletteEntry] {
        var pullRequestsByProject: [String: HyperliteProjectPullRequests] = [:]
        for project in scan?.projects ?? [] {
            pullRequestsByProject[project.id] = project
            pullRequestsByProject[project.path] = project
        }

        var entries: [HyperlitePaletteEntry] = []
        for project in projects {
            let projectPullRequests = pullRequestsByProject[project.id] ??
                pullRequestsByProject[project.path]
            let pullRequests = projectPullRequests?.pullRequests ?? []
            let expanded = expandedProjects.contains(project.id)
            entries.append(HyperlitePaletteEntry(
                id: "project:\(project.id)",
                title: project.name,
                subtitle: projectSummary(
                    pullRequestCount: pullRequests.count,
                    laneCount: project.lanes.count
                ),
                symbol: expanded ? "chevron.down" : "chevron.right",
                kind: .project(project.id)
            ))
            guard expanded else { continue }
            for pullRequest in pullRequests {
                let repository = projectPullRequests?.repository ?? project.repository ?? project.name
                entries.append(HyperlitePaletteEntry(
                    id: "project-pr:\(project.id):\(pullRequest.id)",
                    title: "#\(pullRequest.number) \(pullRequest.title)",
                    subtitle: "\(pullRequest.isDraft ? "draft" : "ready") · " +
                        "\(pullRequest.headRefName) · \(repository)",
                    symbol: "arrow.triangle.pull",
                    kind: .action(.openPullRequest(pullRequest.url)),
                    parentProjectID: project.id
                ))
            }
            for lane in project.lanes {
                entries.append(HyperlitePaletteEntry(
                    id: "project-lane:\(project.id):\(lane.id)",
                    title: "\(HyperliteProjectIndexPresentation.laneKind(lane)) · " +
                        HyperliteProjectIndexPresentation.laneLabel(lane),
                    subtitle: HyperliteProjectIndexPresentation.abbreviatedPath(lane.path),
                    symbol: "folder",
                    kind: .action(.revealPath(lane.path)),
                    parentProjectID: project.id
                ))
            }
        }
        return entries
    }

    static func effectiveProjectExpansion(
        projects: [HyperliteProjectLocation],
        expandedProjects: Set<String>,
        query: String
    ) -> Set<String> {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return expandedProjects
        }
        return Set(projects.map(\.id))
    }

    static func removeProjectEntries(
        projects: [HyperliteProjectLocation]
    ) -> [HyperlitePaletteEntry] {
        projects.map { project in
            actionEntry(
                "remove-project:\(project.id)",
                project.name,
                HyperliteProjectIndexPresentation.abbreviatedPath(project.path),
                "minus.circle",
                .removeProject(project.path)
            )
        }
    }

    static func noteEntries(
        results: [HyperliteNoteSearchResult]
    ) -> [HyperlitePaletteEntry] {
        results.map { result in
            let match = result.matchKind == .exact ? "exact" : "semantic"
            let subtitle = [match, result.filename, result.snippet]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            switch result.noteID {
            case .pinned:
                return actionEntry(
                    result.id, "Pinned", subtitle, "pin.fill", .focusPinnedNote
                )
            case let .daily(date):
                return actionEntry(
                    result.id, date, subtitle, "calendar", .openDailyNote(date)
                )
            }
        }
    }

    static func filteredEntries(
        _ entries: [HyperlitePaletteEntry],
        query: String
    ) -> [HyperlitePaletteEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }

        func matches(_ entry: HyperlitePaletteEntry) -> Bool {
            entry.title.localizedCaseInsensitiveContains(query) ||
                entry.subtitle.localizedCaseInsensitiveContains(query)
        }

        let matchingProjects = Set(entries.compactMap { entry -> String? in
            guard matches(entry), case let .project(projectID) = entry.kind else { return nil }
            return projectID
        })
        let matchingChildParents = Set(entries.compactMap { entry -> String? in
            guard matches(entry) else { return nil }
            return entry.parentProjectID
        })
        return entries.filter { entry in
            if matches(entry) { return true }
            if case let .project(projectID) = entry.kind {
                return matchingChildParents.contains(projectID)
            }
            if let parentProjectID = entry.parentProjectID {
                return matchingProjects.contains(parentProjectID)
            }
            return false
        }
    }

    static func movedSelection(_ selection: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(selection + delta, 0), count - 1)
    }

    static func hoverTitle(for thread: HyperliteThread) -> String {
        truncated("\(thread.projectName) · \(thread.title)", limit: 120)
    }

    static func hoverSummary(for thread: HyperliteThread) -> String {
        truncated("\(thread.phase.label). \(thread.whyNow)", limit: 300)
    }

    static func truncated(_ value: String, limit: Int) -> String {
        guard limit > 0, value.count > limit else { return limit > 0 ? value : "" }
        if limit == 1 { return "…" }
        return String(value.prefix(limit - 1)) + "…"
    }

    private static func projectSummary(pullRequestCount: Int, laneCount: Int) -> String {
        "\(pullRequestCount) PR\(pullRequestCount == 1 ? "" : "s") · " +
            "\(laneCount) lane\(laneCount == 1 ? "" : "s")"
    }

    private static func actionEntry(
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
