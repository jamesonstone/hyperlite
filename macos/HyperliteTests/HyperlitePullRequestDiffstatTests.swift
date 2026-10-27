import Foundation

enum HyperlitePullRequestDiffstatTests {
    static func run() {
        testHidesZeroDiff()
        testFormatsEachNonZeroSide()
        testRowAccessibilityNamesCounts()
        testHoverStillOmitsDiffstat()
    }

    private static func testHidesZeroDiff() {
        let empty = HyperlitePullRequestPresentation.diffstat(additions: 0, deletions: 0)
        expect(!empty.visible && empty.additionsText == nil && empty.deletionsText == nil,
               "a zero diff should stay off the row")
        expect(empty.accessibilityLabel.isEmpty, "a zero diff should stay silent")
    }

    private static func testFormatsEachNonZeroSide() {
        let both = HyperlitePullRequestPresentation.diffstat(additions: 12, deletions: 3)
        expect(both.visible && both.additionsText == "+12" && both.deletionsText == "-3",
               "both sides should show compact signed counts")
        expect(both.accessibilityLabel == "12 added, 3 removed",
               "spoken text should name both sides")

        let added = HyperlitePullRequestPresentation.diffstat(additions: 8, deletions: 0)
        expect(added.visible && added.additionsText == "+8" && added.deletionsText == nil,
               "a zero removed side should stay hidden")

        let removed = HyperlitePullRequestPresentation.diffstat(additions: 0, deletions: 4)
        expect(removed.visible && removed.additionsText == nil && removed.deletionsText == "-4",
               "a zero added side should stay hidden")
    }

    private static func testRowAccessibilityNamesCounts() {
        var glance = HyperlitePullRequestGlance.empty
        glance.additions = 12
        glance.deletions = 3
        let spoken = HyperlitePullRequestRowContent.accessibilityLabel(
            for: row(glance: glance, threads: 2),
            reviewStatus: .unreviewed
        )
        expect(spoken.contains("12 added") && spoken.contains("3 removed"),
               "the row should name the diffstat")
    }

    private static func testHoverStillOmitsDiffstat() {
        var glance = HyperlitePullRequestGlance.empty
        glance.additions = 12
        glance.deletions = 3
        let spoken = HyperlitePullRequestHoverPresentation.snapshot(
            row: row(glance: glance, threads: 2),
            reviewStatus: .unreviewed
        ).accessibilityLabel
        expect(!spoken.contains("+12") && !spoken.contains("12 added"),
               "hover should still omit a dumped diffstat")
    }

    private static func row(
        glance: HyperlitePullRequestGlance,
        threads: Int?
    ) -> HyperlitePullRequestRow {
        HyperlitePullRequestRow(
            id: "one#12", reviewID: "owner/one#12", repository: "owner/one",
            status: .current, number: 12, title: "Ship diffstat",
            url: URL(string: "https://github.com/owner/one/pull/12"),
            headRefOID: "abcdef1", isDraft: false, hasMergeConflict: false,
            unresolvedReviewThreads: threads,
            updatedAt: Date(timeIntervalSince1970: 1_785_850_000),
            glance: glance
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
