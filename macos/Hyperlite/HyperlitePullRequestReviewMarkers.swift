import Foundation

enum HyperlitePullRequestReviewStatus: String, Equatable {
    case unreviewed
    case reviewed
    case stale

    var accessibilityLabel: String {
        switch self {
        case .unreviewed: "not marked reviewed"
        case .reviewed: "marked reviewed for the observed head commit"
        case .stale: "review mark is stale because the head commit changed"
        }
    }
}

enum HyperlitePullRequestLocalReviewFilter: String, CaseIterable, Identifiable {
    case all
    case unreviewed
    case reviewed
    case stale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All review marks"
        case .unreviewed: "Not reviewed by me"
        case .reviewed: "Reviewed by me"
        case .stale: "Review mark stale"
        }
    }
}

struct HyperlitePullRequestReviewMark: Codable, Equatable {
    let repository: String
    let headRefOID: String
    let markedAt: Date
}

enum HyperlitePullRequestReviewPresentation {
    static func status(
        for row: HyperlitePullRequestRow,
        mark: HyperlitePullRequestReviewMark?
    ) -> HyperlitePullRequestReviewStatus {
        guard let mark else { return .unreviewed }
        guard row.status == .current,
              !row.headRefOID.isEmpty,
              !mark.headRefOID.isEmpty,
              row.headRefOID != mark.headRefOID
        else { return .reviewed }
        return .stale
    }
}
