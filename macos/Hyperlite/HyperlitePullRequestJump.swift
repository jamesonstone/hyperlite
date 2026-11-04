import Foundation

/// `<project> <number>` in Command-P: the number matches a pull request
/// number or the issue a pull request tracks (`GH-<n>` or a stamped key
/// such as `ENG-67`).
struct HyperlitePullRequestJumpQuery: Equatable {
    let project: String
    let number: Int
    /// Set when the query names a ticket key such as `ENG-67` rather than a number.
    let issueLabel: String? = nil
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
        let project = words.joined(separator: " ")
        if let number = numberToken(last) {
            return HyperlitePullRequestJumpQuery(project: project, number: number)
        }
        if let key = linearToken(last) {
            return HyperlitePullRequestJumpQuery(project: project, number: -1, issueLabel: key)
        }
        return nil
    }

    private static func numberToken(_ last: String) -> Int? {
        var digits = last.lowercased()
        for prefix in ["#", "gh-", "pr#", "pr"] where digits.hasPrefix(prefix) {
            digits.removeFirst(prefix.count)
            break
        }
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let number = Int(digits) else { return nil }
        return number
    }

    /// A Linear-shaped key. `GH-<n>` stays a number query.
    private static func linearToken(_ last: String) -> String? {
        let token = last.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.range(of: #"^[A-Za-z][A-Za-z0-9]{1,6}-[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let key = token.uppercased()
        return key.hasPrefix("GH-") ? nil : key
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
                let tracked = trackedIssueLabel(pullRequest)
                if jump.issueLabel == nil && pullRequest.number == jump.number {
                    pullRequestMatches.append(entry(
                        rowID, "PR #\(pullRequest.number) · \(HyperliteEmoji.render(pullRequest.title))",
                        "pull request #\(jump.number) in \(repository)"
                    ))
                } else if let tracked, jumpMatches(jump, tracked) {
                    let subtitle = jump.issueLabel == nil
                        ? "issue #\(jump.number) in \(repository)"
                        : "issue \(tracked) in \(repository)"
                    issueMatches.append(entry(
                        rowID, "\(tracked) → PR #\(pullRequest.number) · \(HyperliteEmoji.render(pullRequest.title))",
                        subtitle
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

    private static func trackedIssueLabel(_ pullRequest: HyperliteProjectPullRequest) -> String? {
        if !pullRequest.issueLabel.isEmpty { return pullRequest.issueLabel }
        return HyperliteIssueReference.number(branch: pullRequest.headRefName, title: pullRequest.title).map { "GH-\($0)" }
    }

    private static func jumpMatches(_ jump: HyperlitePullRequestJumpQuery, _ label: String) -> Bool {
        if let want = jump.issueLabel {
            return label.caseInsensitiveCompare(want) == .orderedSame
        }
        return label == "GH-\(jump.number)"
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
