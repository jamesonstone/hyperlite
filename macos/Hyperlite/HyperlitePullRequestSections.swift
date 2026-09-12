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
    /// in configuration order. Two configured paths for one repository
    /// collapse into a single section.
    static func sections(
        scan: HyperliteProjectPullRequestScan,
        groups: [HyperlitePullRequestPinning.ProjectGroup]
    ) -> [HyperliteProjectSection] {
        var projectsByKey: [String: HyperliteProjectPullRequests] = [:]
        var order: [String] = []
        for project in scan.projects {
            let key = project.repository ?? project.name
            guard projectsByKey[key] == nil else { continue }
            projectsByKey[key] = project
            order.append(key)
        }
        var result: [HyperliteProjectSection] = []
        var used = Set<String>()
        for group in groups {
            guard let project = projectsByKey[group.repository] else { continue }
            used.insert(group.repository)
            result.append(HyperliteProjectSection(
                id: project.id, repository: group.repository, project: project, rows: group.rows
            ))
        }
        for key in order where !used.contains(key) {
            guard let project = projectsByKey[key] else { continue }
            result.append(HyperliteProjectSection(
                id: project.id, repository: key, project: project, rows: []
            ))
        }
        return result
    }
}
