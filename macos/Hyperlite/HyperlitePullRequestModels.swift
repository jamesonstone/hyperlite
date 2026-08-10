import Foundation

struct HyperliteProjectPullRequestScan: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let checkedAt: Date?
    let observedAt: Date?
    let rateLimit: HyperliteGitHubRateLimit?
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
        case rateLimit = "rate_limit"
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
    let headRefOID: String
    let isDraft: Bool
    let unresolvedReviewThreads: Int?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, number, title, url
        case headRefName = "head_ref_name"
        case headRefOID = "head_ref_oid"
        case isDraft = "is_draft"
        case unresolvedReviewThreads = "unresolved_review_threads"
        case updatedAt = "updated_at"
    }
}

struct HyperlitePullRequestRow: Equatable, Identifiable {
    let id: String
    let reviewID: String
    let repository: String
    let status: HyperliteProjectPullRequestStatus
    let number: Int
    let title: String
    let url: URL?
    let headRefOID: String
    let isDraft: Bool
    let unresolvedReviewThreads: Int?
    let updatedAt: Date
}

struct HyperlitePullRequestRowLayout: Equatable {
    let repositoryColumnWidth: CGFloat
    let reviewFeedbackColumnWidth: CGFloat
    let availabilityMetadataColumnWidth: CGFloat
    let repositoryLayoutPriority: Double
    let titleLayoutPriority: Double

    static let repositoryFirst = HyperlitePullRequestRowLayout(
        repositoryColumnWidth: 190,
        reviewFeedbackColumnWidth: 28,
        availabilityMetadataColumnWidth: 126,
        repositoryLayoutPriority: 1,
        titleLayoutPriority: -1
    )
}

struct HyperliteReviewFeedbackPresentation: Equatable {
    let text: String
    let accessibilityLabel: String
    let needsAttention: Bool
}

enum HyperlitePullRequestPresentation {
    static func rows(scan: HyperliteProjectPullRequestScan) -> [HyperlitePullRequestRow] {
        scan.projects.flatMap { project in
            project.pullRequests.map { pullRequest in
                HyperlitePullRequestRow(
                    id: "\(project.id)\u{1F}\(pullRequest.id)",
                    reviewID: pullRequest.id,
                    repository: project.repository ?? project.name,
                    status: project.status,
                    number: pullRequest.number,
                    title: pullRequest.title,
                    url: URL(string: pullRequest.url),
                    headRefOID: pullRequest.headRefOID,
                    isDraft: pullRequest.isDraft,
                    unresolvedReviewThreads: pullRequest.unresolvedReviewThreads,
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
        if scan.projects.contains(where: { project in
            project.status == .current && project.pullRequests.contains {
                $0.unresolvedReviewThreads == nil || $0.headRefOID.isEmpty
            }
        }) {
            return true
        }
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

    static func reviewFeedback(
        unresolvedThreads: Int?
    ) -> HyperliteReviewFeedbackPresentation {
        guard let unresolvedThreads else {
            return HyperliteReviewFeedbackPresentation(
                text: "?",
                accessibilityLabel: "review feedback count unavailable",
                needsAttention: false
            )
        }
        guard unresolvedThreads > 0 else {
            return HyperliteReviewFeedbackPresentation(
                text: "—",
                accessibilityLabel: "no unresolved review threads",
                needsAttention: false
            )
        }
        return HyperliteReviewFeedbackPresentation(
            text: "\(unresolvedThreads)",
            accessibilityLabel: "\(unresolvedThreads) unresolved review " +
                "thread\(unresolvedThreads == 1 ? "" : "s")",
            needsAttention: true
        )
    }
}
