import Foundation

struct HyperliteProjectLocation: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let path: String
    let repository: String?
    let lanes: [HyperliteProjectLane]
}

struct HyperliteProjectLane: Codable, Equatable, Identifiable {
    let id: String
    let branch: String?
    let path: String
    let primary: Bool
    let detached: Bool
}

enum HyperliteProjectIndexPresentation {
    static func visibleProjects(
        _ projects: [HyperliteProjectLocation],
        pullRequests scan: HyperliteProjectPullRequestScan?
    ) -> [HyperliteProjectLocation] {
        var branchesByProject: [String: Set<String>] = [:]
        for project in scan?.projects ?? [] {
            branchesByProject[project.id, default: []].formUnion(
                project.pullRequests.map(\.headRefName).filter { !$0.isEmpty }
            )
        }
        return projects.map { project in
            let openBranches = branchesByProject[project.id] ?? []
            let lanes = project.lanes.filter { lane in
                guard !lane.primary else { return true }
                guard let branch = lane.branch else { return false }
                return openBranches.contains(branch)
            }
            return HyperliteProjectLocation(
                id: project.id,
                name: project.name,
                path: project.path,
                repository: project.repository,
                lanes: lanes
            )
        }
    }

    static func laneLabel(_ lane: HyperliteProjectLane) -> String {
        if let branch = lane.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty
        {
            return branch
        }
        return lane.detached ? "detached" : "checkout"
    }

    static func abbreviatedPath(
        _ path: String,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        let standardizedPath = (path as NSString).standardizingPath
        let standardizedHome = (home as NSString).standardizingPath
        if standardizedPath == standardizedHome {
            return "~"
        }
        let prefix = standardizedHome + "/"
        guard standardizedPath.hasPrefix(prefix) else { return standardizedPath }
        return "~/" + standardizedPath.dropFirst(prefix.count)
    }
}
