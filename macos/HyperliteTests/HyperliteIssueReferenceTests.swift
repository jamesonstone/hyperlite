import Foundation

enum HyperliteIssueReferenceTests {
    static func run() {
        testExtractsFromBranchAndTitle()
        testNoFalsePositives()
        testRowLinksToTrackedIssue()
        testRowFallsBackToPullRequest()
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
    }

    private static func testRowLinksToTrackedIssue() {
        let row = row(
            number: 539, repository: "lsmc-bio/labcore-ui",
            headRefName: "GH-538", title: "feat(GH-538): rename accessioning field"
        )
        expect(row.displayNumber == 538 && row.numberOpensIssue,
               "a linked row shows and opens the issue number, not the pull request number")
        expect(row.numberURL?.absoluteString == "https://github.com/lsmc-bio/labcore-ui/issues/538",
               "the number opens the tracked issue; got \(row.numberURL?.absoluteString ?? "nil")")
    }

    private static func testRowFallsBackToPullRequest() {
        let row = row(
            number: 46, repository: "jamesonstone/rungrid",
            headRefName: "dependabot/go_modules/golang.org/x/sys-0.48.0",
            title: "build(deps): bump golang.org/x/sys from 0.47.0 to 0.48.0"
        )
        expect(row.displayNumber == 46 && !row.numberOpensIssue,
               "an unlinked row keeps the pull request number")
        expect(row.numberURL == row.url,
               "the number opens the pull request when no issue is tracked")
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
