import Foundation

enum HyperlitePullRequestStateFilter: String, CaseIterable, Identifiable {
    case all, ready, draft

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum HyperlitePullRequestReviewFilter: String, CaseIterable, Identifiable {
    case all, attention, clear, unavailable

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All review states"
        case .attention: "Needs attention"
        case .clear: "No unresolved feedback"
        case .unavailable: "Feedback unavailable"
        }
    }
}

enum HyperlitePullRequestDataFilter: String, CaseIterable, Identifiable {
    case all, current, cached, unavailable

    var id: String { rawValue }
    var title: String { rawValue == "all" ? "All data states" : rawValue.capitalized }
}

struct HyperlitePullRequestFilter: Equatable {
    var query = ""
    var repository = ""
    var state: HyperlitePullRequestStateFilter = .all
    var review: HyperlitePullRequestReviewFilter = .all
    var localReview: HyperlitePullRequestLocalReviewFilter = .all
    var data: HyperlitePullRequestDataFilter = .all

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !repository.isEmpty || state != .all || review != .all ||
            localReview != .all || data != .all
    }
}
