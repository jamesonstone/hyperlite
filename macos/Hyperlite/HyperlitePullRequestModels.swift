import Foundation

struct HyperliteProjectPullRequestScan: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let checkedAt: Date?
    let observedAt: Date?
    let refreshIntervalSeconds: Int
    let projects: [HyperliteProjectPullRequests]
    let errors: [HyperliteDiagnostic]
    let warnings: [HyperliteDiagnostic]

    enum CodingKeys: String, CodingKey {
        case projects, errors, warnings
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case checkedAt = "checked_at"
        case observedAt = "observed_at"
        case refreshIntervalSeconds = "refresh_interval_seconds"
    }
}

enum HyperliteProjectPullRequestStatus: String, Codable, Equatable {
    case current
    case cached
    case unavailable
}

struct HyperliteProjectPullRequests: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let path: String
    let repository: String?
    let status: HyperliteProjectPullRequestStatus
    let message: String?
    let checkedAt: Date?
    let observedAt: Date?
    let pullRequests: [HyperliteProjectPullRequest]

    enum CodingKeys: String, CodingKey {
        case id, name, path, repository, status, message
        case checkedAt = "checked_at"
        case observedAt = "observed_at"
        case pullRequests = "pull_requests"
    }
}

struct HyperliteProjectPullRequest: Codable, Equatable, Identifiable {
    let id: String
    let number: Int
    let title: String
    let url: String
    let headRefName: String
    let isDraft: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, number, title, url
        case headRefName = "head_ref_name"
        case isDraft = "is_draft"
        case updatedAt = "updated_at"
    }
}

struct HyperlitePullRequestRow: Equatable, Identifiable {
    let id: String
    let repository: String
    let status: HyperliteProjectPullRequestStatus
    let number: Int
    let title: String
    let url: URL?
    let isDraft: Bool
    let updatedAt: Date
}

struct HyperlitePullRequestRowLayout: Equatable {
    let repositoryColumnWidth: CGFloat
    let repositoryLayoutPriority: Double
    let titleLayoutPriority: Double

    static let repositoryFirst = HyperlitePullRequestRowLayout(
        repositoryColumnWidth: 190,
        repositoryLayoutPriority: 1,
        titleLayoutPriority: -1
    )
}

enum HyperlitePullRequestPresentation {
    static func rows(scan: HyperliteProjectPullRequestScan) -> [HyperlitePullRequestRow] {
        scan.projects.flatMap { project in
            project.pullRequests.map { pullRequest in
                HyperlitePullRequestRow(
                    id: "\(project.id)\u{1F}\(pullRequest.id)",
                    repository: project.repository ?? project.name,
                    status: project.status,
                    number: pullRequest.number,
                    title: pullRequest.title,
                    url: URL(string: pullRequest.url),
                    isDraft: pullRequest.isDraft,
                    updatedAt: pullRequest.updatedAt
                )
            }
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.repository != $1.repository { return $0.repository < $1.repository }
            return $0.number < $1.number
        }
    }

    static func availability(
        scan: HyperliteProjectPullRequestScan
    ) -> [HyperliteProjectPullRequests] {
        scan.projects.filter { $0.status != .current }
    }

    static func isStale(
        scan: HyperliteProjectPullRequestScan,
        now: Date = Date()
    ) -> Bool {
        guard let checkedAt = scan.checkedAt else { return true }
        let interval = max(300, scan.refreshIntervalSeconds)
        return now.timeIntervalSince(checkedAt) >= Double(interval)
    }

    static func freshnessLabel(
        observedAt: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        guard let observedAt else { return "GitHub availability limited" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Updated \(formatter.string(from: observedAt))"
    }
}
