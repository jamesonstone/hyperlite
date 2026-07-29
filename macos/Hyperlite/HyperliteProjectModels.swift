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
