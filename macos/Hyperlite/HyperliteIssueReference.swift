import Foundation

/// Recovers the GitHub issue a pull request tracks. Hyperlite projects name
/// branches and conventional-commit titles `GH-<number>`, so the tracked issue
/// is derivable from the head branch first and the title as a fallback.
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

    /// The number shown in the row: the tracked issue when known, else the
    /// pull request's own number.
    var displayNumber: Int { linkedIssueNumber ?? number }

    var numberOpensIssue: Bool { linkedIssueNumber != nil }

    var issueURL: URL? {
        guard let issue = linkedIssueNumber, repository.contains("/") else { return nil }
        return URL(string: "https://github.com/\(repository)/issues/\(issue)")
    }

    /// Where the number chip navigates: the tracked issue when known, else the
    /// pull request itself.
    var numberURL: URL? { issueURL ?? url }
}
