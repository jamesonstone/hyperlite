import Foundation

struct HyperlitePullRequestDiffstat: Equatable {
    let additions: Int
    let deletions: Int

    var visible: Bool { additions > 0 || deletions > 0 }

    var additionsText: String? {
        additions > 0 ? "+\(additions)" : nil
    }

    var deletionsText: String? {
        deletions > 0 ? "-\(deletions)" : nil
    }

    var accessibilityLabel: String {
        var parts: [String] = []
        if additions > 0 { parts.append("\(additions) added") }
        if deletions > 0 { parts.append("\(deletions) removed") }
        return parts.joined(separator: ", ")
    }
}

extension HyperlitePullRequestPresentation {
    static func diffstat(additions: Int, deletions: Int) -> HyperlitePullRequestDiffstat {
        HyperlitePullRequestDiffstat(additions: additions, deletions: deletions)
    }
}
