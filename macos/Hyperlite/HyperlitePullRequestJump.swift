import Foundation

/// `<project> <number>` in Command-P: the number matches a pull request
/// number or the issue a pull request tracks (`GH-<n>`).
struct HyperlitePullRequestJumpQuery: Equatable {
    let project: String
    let number: Int
}

/// A request for the Open PRs list to bring an entry on screen. `token`
/// makes repeated requests for the same entry distinct.
struct HyperliteScrollRequest: Equatable {
    let id: String
    let centered: Bool
    let token: Int
}

enum HyperlitePullRequestJump {
    static func parse(_ query: String) -> HyperlitePullRequestJumpQuery? {
        var words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2, let last = words.popLast() else { return nil }
        var digits = last.lowercased()
        for prefix in ["#", "gh-", "pr#", "pr"] where digits.hasPrefix(prefix) {
            digits.removeFirst(prefix.count)
            break
        }
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let number = Int(digits) else { return nil }
        return HyperlitePullRequestJumpQuery(project: words.joined(separator: " "), number: number)
    }

    /// Palette entries for a jump query, or nil when the query is not one or
    /// matches nothing, so ordinary project filtering still applies.
    static func entries(
        query: String,
        scan: HyperliteProjectPullRequestScan?
    ) -> [HyperlitePaletteEntry]? {
        guard let jump = parse(query), let scan else { return nil }
        var pullRequestMatches: [HyperlitePaletteEntry] = []
        var issueMatches: [HyperlitePaletteEntry] = []
        for project in scan.projects where !project.isIgnored && matches(project, jump.project) {
            let repository = project.repository ?? project.name
            for pullRequest in project.pullRequests {
                let rowID = rowID(projectID: project.id, pullRequestID: pullRequest.id)
                let issue = HyperliteIssueReference.number(branch: pullRequest.headRefName, title: pullRequest.title)
                if pullRequest.number == jump.number {
                    pullRequestMatches.append(entry(
                        rowID, "PR #\(pullRequest.number) · \(HyperliteEmoji.render(pullRequest.title))",
                        "pull request #\(jump.number) in \(repository)"
                    ))
                } else if issue == jump.number {
                    issueMatches.append(entry(
                        rowID, "GH-\(jump.number) → PR #\(pullRequest.number) · \(HyperliteEmoji.render(pullRequest.title))",
                        "issue #\(jump.number) in \(repository)"
                    ))
                }
            }
        }
        let results = pullRequestMatches + issueMatches
        return results.isEmpty ? nil : results
    }

    /// The Open PRs row identity, shared with HyperlitePullRequestPresentation.rows.
    static func rowID(projectID: String, pullRequestID: String) -> String {
        "\(projectID)\u{1F}\(pullRequestID)"
    }

    /// The project section that contains a row or heading, so a lazily built
    /// section can be scrolled into existence before the entry itself.
    static func sectionID(for entryID: String) -> String? {
        if let projectID = entryID.split(separator: "\u{1F}", maxSplits: 1).first, entryID.contains("\u{1F}") {
            return String(projectID)
        }
        let prefix = HyperliteWorkspaceNavigation.headerID(sectionID: "")
        return entryID.hasPrefix(prefix) ? String(entryID.dropFirst(prefix.count)) : nil
    }

    private static func matches(_ project: HyperliteProjectPullRequests, _ term: String) -> Bool {
        project.name.localizedCaseInsensitiveContains(term) ||
            (project.repository ?? "").localizedCaseInsensitiveContains(term)
    }

    private static func entry(_ rowID: String, _ title: String, _ subtitle: String) -> HyperlitePaletteEntry {
        HyperlitePaletteEntry(
            id: "jump:\(rowID)", title: title, subtitle: subtitle,
            symbol: "arrow.triangle.pull", kind: .action(.selectPullRequest(rowID))
        )
    }
}
