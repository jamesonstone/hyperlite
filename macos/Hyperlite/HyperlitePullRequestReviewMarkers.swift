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
