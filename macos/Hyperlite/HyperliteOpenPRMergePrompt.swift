import Foundation

enum HyperliteOpenPRMergePrompt {
    static let confirmationDuration: Duration = .seconds(2)
    static let copyAccessibilityLabel =
        "Copy merge-ready prompt for visible open pull requests"
    static let copiedAccessibilityLabel = "Copied merge-ready prompt"
    static let instructions = """
        Update each listed GitHub pull request until it is ready to merge.

        Use the `gh` CLI as the source of current GitHub evidence. Work through the list in order. For every pull request:

        - Refresh current review and mergeability evidence.
        - Resolve merge conflicts on the head branch.
        - Address unresolved review threads and review comments.
        - Bring the head branch up to date with the repository default branch.
        - Convert a draft to ready only after remaining merge blockers are cleared.
        - Do not merge, close, or delete the pull request unless a later operator request says so.

        The observations below are Hyperlite's currently visible Open PRs list. Treat them as hints, not live GitHub truth. Hyperlite does not observe whether a branch is behind the default branch; check that with `gh`.
        """

    static func text(rows: [HyperlitePullRequestRow]) -> String {
        let list = rows.isEmpty
            ? "(none)"
            : rows.map(line(for:)).joined(separator: "\n")
        return instructions + "\n\n## Visible Open PRs\n\n" + list + "\n"
    }

    static func line(for row: HyperlitePullRequestRow) -> String {
        var parts = ["\(row.repository)#\(row.number)"]
        if let url = row.url {
            parts.append(url.absoluteString)
        }
        parts.append(observations(for: row))
        return "- " + parts.joined(separator: " — ")
    }

    static func commandTitle(copied: Bool) -> String {
        copied ? "Copied Open PR Merge Prompt" : "Copy Open PR Merge Prompt"
    }

    static func commandSubtitle(visibleCount: Int, copied: Bool) -> String {
        if copied { return "Copied to clipboard" }
        if visibleCount == 0 { return "No visible open pull requests" }
        let noun = visibleCount == 1 ? "PR" : "PRs"
        return "\(visibleCount) visible \(noun) · clipboard for a coding agent"
    }

    static func commandSymbol(copied: Bool) -> String {
        copied ? "checkmark.circle.fill" : "doc.on.clipboard"
    }

    private static func observations(for row: HyperlitePullRequestRow) -> String {
        let state = row.isDraft ? "draft" : "ready"
        let conflict = row.hasMergeConflict ? "merge conflicts" : "no merge conflicts"
        return "\(state); \(conflict); \(reviewThreads(row.unresolvedReviewThreads))"
    }

    private static func reviewThreads(_ count: Int?) -> String {
        switch count {
        case nil: "unresolved review threads unknown"
        case 0: "no unresolved review threads"
        case 1: "1 unresolved review thread"
        case let value?: "\(value) unresolved review threads"
        }
    }
}
