import Foundation

/// One Open PRs section per configured project. Projects without open pull
/// requests still get a section so their workflow strip and GitHub links
/// remain visible right after a merge, when the PR row disappears.
struct HyperliteProjectSection: Equatable, Identifiable {
    let id: String
    let repository: String
    let project: HyperliteProjectPullRequests
    let rows: [HyperlitePullRequestRow]

    var pullsURL: URL? { githubURL("pulls") }
    var actionsURL: URL? { githubURL("actions") }
    var repositoryURL: URL? {
        guard let repo = project.repository, repo.contains("/") else { return nil }
        return URL(string: "https://github.com/\(repo)")
    }
    var pullsButtonLabel: String { "Open pull requests for \(repository) on GitHub" }
    var actionsButtonLabel: String { "Open GitHub Actions for \(repository)" }

    var idleText: String {
        switch project.status {
        case .current: "no open pull requests"
        case .cached: "cached · \(project.message ?? "GitHub data is unavailable")"
        case .unavailable: "unavailable · \(project.message ?? "GitHub data is unavailable")"
        }
    }

    private func githubURL(_ path: String) -> URL? {
        guard let repo = project.repository, repo.contains("/") else { return nil }
        return URL(string: "https://github.com/\(repo)/\(path)")
    }
}

enum HyperlitePullRequestSectionPlan {
    /// Groups with rows keep the pin store's project order so drag and move
    /// across project groups still work; projects without unpinned rows follow
    /// in configuration order. Sections are keyed by project identity, so two
    /// configured projects that point at one repository each keep a section.
    static func sections(
        scan: HyperliteProjectPullRequestScan,
        groups: [HyperlitePullRequestPinning.ProjectGroup]
    ) -> [HyperliteProjectSection] {
        var projectsByID: [String: HyperliteProjectPullRequests] = [:]
        var order: [String] = []
        for project in scan.projects {
            guard projectsByID[project.id] == nil else { continue }
            projectsByID[project.id] = project
            order.append(project.id)
        }
        var result: [HyperliteProjectSection] = []
        var used = Set<String>()
        for group in groups {
            guard let project = projectsByID[group.projectID] else { continue }
            used.insert(group.projectID)
            result.append(section(for: project, rows: group.rows))
        }
        for id in order where !used.contains(id) {
            guard let project = projectsByID[id] else { continue }
            result.append(section(for: project, rows: []))
        }
        return result
    }

    private static func section(
        for project: HyperliteProjectPullRequests,
        rows: [HyperlitePullRequestRow]
    ) -> HyperliteProjectSection {
        HyperliteProjectSection(
            id: project.id, repository: project.repository ?? project.name,
            project: project, rows: rows
        )
    }
}

enum HyperliteProjectSectionChrome {
    enum HeadingWeight: Equatable {
        case active
        case notable
        case idle
    }

    static func headingWeight(
        idle: Bool,
        chips: [HyperliteWorkflowChip]
    ) -> HeadingWeight {
        if !idle { return .active }
        if chips.contains(where: { $0.isRunning || $0.needsAttention }) {
            return .notable
        }
        return .idle
    }

    static func stripChips(
        _ chips: [HyperliteWorkflowChip],
        idle: Bool,
        compact: Bool
    ) -> [HyperliteWorkflowChip] {
        if idle || compact {
            return chips.filter { $0.isRunning || $0.needsAttention }
        }
        return chips
    }
}

/// Filters the project sections when the user chooses to hide idle projects.
/// A project stays visible while it has open pull requests or a workflow worth
/// attention (running or failing), so hiding declutters the list without
/// losing an in-flight deploy that has no open pull request.
enum HyperliteOpenPRProjectFilter {
    static func hasNotableActivity(_ section: HyperliteProjectSection, now: Date) -> Bool {
        HyperliteWorkflowStripPresentation
            .chips(activity: section.project.workflows, now: now)
            .contains { $0.isRunning || $0.needsAttention }
    }

    static func isIdle(_ section: HyperliteProjectSection, now: Date) -> Bool {
        section.rows.isEmpty && !hasNotableActivity(section, now: now)
    }

    static func visibleSections(
        _ sections: [HyperliteProjectSection],
        hideIdle: Bool,
        now: Date
    ) -> [HyperliteProjectSection] {
        guard hideIdle else { return sections }
        return sections.filter { !isIdle($0, now: now) }
    }
}
