import Foundation

enum HyperlitePullRequestCommentsColumn: Equatable {
    case threads(Int)
    case pending
    case clear

    var accessibilityLabel: String {
        switch self {
        case .threads(let count):
            "\(count) unresolved review thread\(count == 1 ? "" : "s")"
        case .pending:
            "CI pending"
        case .clear:
            "no unresolved review threads"
        }
    }
}

extension HyperlitePullRequestPresentation {
    static func commentsColumn(
        unresolvedThreads: Int?,
        ciState: String
    ) -> HyperlitePullRequestCommentsColumn {
        if let unresolvedThreads, unresolvedThreads > 0 {
            return .threads(unresolvedThreads)
        }
        switch ciState.uppercased() {
        case "PENDING", "EXPECTED":
            return .pending
        default:
            return .clear
        }
    }
}
