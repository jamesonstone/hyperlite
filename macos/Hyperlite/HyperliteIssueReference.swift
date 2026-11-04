import Foundation

/// Recovers a GitHub issue number from the `GH-<number>` convention. The
/// helper stamps Linear and GitHub links onto each row; this fallback covers
/// a payload that has no stamped label.
enum HyperliteIssueReference {
    static func number(branch: String, title: String) -> Int? {
        ghNumber(in: branch) ?? ghNumber(in: title)
    }

    private static func ghNumber(in text: String) -> Int? {
        // Word boundaries on both sides keep "high-5" and "GH-12foo" from
        // matching: the leading boundary rejects GH inside a word, and the
        // trailing boundary requires a complete GH-<number> token.
        guard let range = text.range(of: "\\bGH-[0-9]+\\b", options: .regularExpression) else {
            return nil
        }
        return Int(text[range].dropFirst(3))
    }
}

extension HyperlitePullRequestRow {
    /// The issue this pull request tracks, when its branch or title names one.
    var linkedIssueNumber: Int? {
        HyperliteIssueReference.number(branch: headRefName, title: title)
    }

    /// The pull request's own number, labeled so it never reads as the issue.
    var pullRequestLabel: String { "PR #\(number)" }

    /// The tracked issue. A label stamped by the helper wins, including a
    /// Linear key. Otherwise the row still recognizes `GH-<n>`.
    var issueLabel: String? {
        if !resolvedIssueLabel.isEmpty { return resolvedIssueLabel }
        return linkedIssueNumber.map { "GH-\($0)" }
    }

    var issueURL: URL? {
        if !resolvedIssueLabel.isEmpty { return resolvedIssueURL }
        guard let issue = linkedIssueNumber, repository.contains("/") else { return nil }
        return URL(string: "https://github.com/\(repository)/issues/\(issue)")
    }
}
