import Foundation

enum HyperliteIssueReferenceTests {
    static func run() throws {
        testExtractsFromBranchAndTitle()
        testNoFalsePositives()
        testRowLinksToTrackedIssue()
        testRowFallsBackToPullRequest()
        testResolvedLinkWins()
        try testDecodedProviderLinks()
    }

    private static func testExtractsFromBranchAndTitle() {
        expect(HyperliteIssueReference.number(branch: "GH-538", title: "feat: rename field") == 538,
               "the head branch names the tracked issue")
        expect(HyperliteIssueReference.number(branch: "feature/x", title: "feat(GH-96): show workflows") == 96,
               "the title names the issue when the branch does not")
        expect(HyperliteIssueReference.number(branch: "", title: "build(deps): bump x") == nil,
               "a title without a ticket yields no issue")
    }

    private static func testNoFalsePositives() {
        expect(HyperliteIssueReference.number(branch: "high-5", title: "cough-9 tough-2") == nil,
               "GH inside a word must not match the ticket convention")
        expect(HyperliteIssueReference.number(branch: "gh-12", title: "") == nil,
               "the convention is uppercase GH-, so lowercase does not match")
        expect(HyperliteIssueReference.number(branch: "GH-12foo", title: "GH-34bar") == nil,
               "a number followed by more word characters is not a complete GH- token")
        expect(HyperliteIssueReference.number(branch: "GH-12-cleanup", title: "") == 12,
               "a non-word separator after the number still completes the token")
    }

    private static func testRowLinksToTrackedIssue() {
        let row = row(
            number: 539, repository: "lsmc-bio/labcore-ui",
            headRefName: "GH-538", title: "feat(GH-538): rename accessioning field"
        )
        expect(row.pullRequestLabel == "PR #539" && row.issueLabel == "GH-538",
               "a linked row labels both the pull request and the issue")
        expect(row.issueURL?.absoluteString == "https://github.com/lsmc-bio/labcore-ui/issues/538",
               "the issue label opens the tracked issue; got \(row.issueURL?.absoluteString ?? "nil")")
    }

    private static func testRowFallsBackToPullRequest() {
        let row = row(
            number: 46, repository: "jamesonstone/rungrid",
            headRefName: "dependabot/go_modules/golang.org/x/sys-0.48.0",
            title: "build(deps): bump golang.org/x/sys from 0.47.0 to 0.48.0"
        )
        expect(row.pullRequestLabel == "PR #46" && row.issueLabel == nil && row.issueURL == nil,
               "an unlinked row shows only the pull request number")
    }

    private static func testResolvedLinkWins() {
        var row = row(
            number: 1329, repository: "lsmc-bio/labcore",
            headRefName: "GH-1265", title: "fix(ENG-67): admit buccal partner orders"
        )
        row.resolvedIssueLabel = "ENG-67"
        row.resolvedIssueURL = URL(string: "https://linear.app/lsmc/issue/ENG-67")
        expect(row.issueLabel == "ENG-67", "a stamped Linear key replaces the GitHub fallback")
        expect(row.issueURL?.absoluteString == "https://linear.app/lsmc/issue/ENG-67",
               "the stamped key opens the Linear ticket; got \(row.issueURL?.absoluteString ?? "nil")")
    }

    private static func testDecodedProviderLinks() throws {
        let scan = try HyperliteJSON.decoder.decode(HyperliteProjectPullRequestScan.self, from: Data("""
        {"schema_version": 1, "generated_at": "2026-11-04T18:00:00Z", "refresh_interval_seconds": 300,
         "projects": [
          {"id": "/labcore", "name": "labcore", "path": "/labcore", "repository": "lsmc-bio/labcore",
           "status": "current", "pull_requests": [
            {"id": "lsmc-bio/labcore#1329", "number": 1329, "title": "fix(ENG-67): admit",
             "url": "https://github.com/lsmc-bio/labcore/pull/1329", "head_ref_name": "ENG-67",
             "head_ref_oid": "h", "is_draft": false, "updated_at": "2026-11-04T18:00:00Z",
             "issue_label": "ENG-67", "issue_url": "https://linear.app/lsmc/issue/ENG-67"}]},
          {"id": "/docs", "name": "docs", "path": "/docs", "repository": "lsmc-bio/docs",
           "status": "current", "pull_requests": [
            {"id": "lsmc-bio/docs#1266", "number": 1266, "title": "validate",
             "url": "https://github.com/lsmc-bio/docs/pull/1266", "head_ref_name": "GH-1265",
             "head_ref_oid": "h", "is_draft": false, "updated_at": "2026-11-04T17:00:00Z",
             "issue_label": "GH-1265", "issue_url": "https://github.com/lsmc-bio/docs/issues/1265"}]},
          {"id": "/legacy", "name": "legacy", "path": "/legacy", "repository": "o/legacy",
           "status": "current", "pull_requests": [
            {"id": "o/legacy#3", "number": 3, "title": "old",
             "url": "https://github.com/o/legacy/pull/3", "head_ref_name": "GH-3",
             "head_ref_oid": "h", "is_draft": false, "updated_at": "2026-11-04T16:00:00Z"}]}
         ], "errors": [], "warnings": []}
        """.utf8))
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        expect(rows.map(\.issueLabel) == ["ENG-67", "GH-1265", "GH-3"],
               "newer rows first; legacy payload still derives GH-3; got \(rows.map(\.issueLabel))")
        expect(rows[0].issueURL?.absoluteString == "https://linear.app/lsmc/issue/ENG-67" &&
               rows[1].issueURL?.absoluteString == "https://github.com/lsmc-bio/docs/issues/1265" &&
               rows[2].issueURL?.absoluteString == "https://github.com/o/legacy/issues/3",
               "each provider keeps its own issue URL")
    }

    private static func row(
        number: Int, repository: String, headRefName: String, title: String
    ) -> HyperlitePullRequestRow {
        HyperlitePullRequestRow(
            id: "\(repository)#\(number)", reviewID: "\(repository)#\(number)",
            repository: repository, status: .current, number: number, title: title,
            url: URL(string: "https://github.com/\(repository)/pull/\(number)"),
            headRefName: headRefName, headRefOID: "head", isDraft: false,
            hasMergeConflict: false, unresolvedReviewThreads: 0, updatedAt: Date()
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
