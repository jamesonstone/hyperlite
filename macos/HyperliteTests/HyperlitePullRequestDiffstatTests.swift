import Foundation

enum HyperlitePullRequestDiffstatTests {
    static func run() {
        testHidesZeroDiff()
        testFormatsEachNonZeroSide()
        testCommentsColumnStates()
        testTrailingColumnsReserveWidth()
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

    private static func testCommentsColumnStates() {
        let threads = HyperlitePullRequestPresentation.commentsColumn(
            unresolvedThreads: 3, ciState: "PENDING"
        )
        expect(
            threads == .threads(3) &&
                threads.accessibilityLabel == "3 unresolved review threads",
            "unresolved threads win over pending CI"
        )
        let pending = HyperlitePullRequestPresentation.commentsColumn(
            unresolvedThreads: 0, ciState: "PENDING"
        )
        expect(pending == .pending && pending.accessibilityLabel == "CI pending",
               "pending CI with no threads should show the cycling state")
        let expected = HyperlitePullRequestPresentation.commentsColumn(
            unresolvedThreads: nil, ciState: "EXPECTED"
        )
        expect(expected == .pending, "expected CI should use the cycling state")
        let clear = HyperlitePullRequestPresentation.commentsColumn(
            unresolvedThreads: 0, ciState: "SUCCESS"
        )
        expect(
            clear == .clear &&
                clear.accessibilityLabel == "no unresolved review threads",
            "a quiet row should show the clear check"
        )
    }

    private static func testTrailingColumnsReserveWidth() {
        let layout = HyperlitePullRequestRowLayout.titleFirst
        expect(HyperlitePullRequestRowLayout.additionsColumnWidth >= 48,
               "added column should fit a six-digit signed count")
        expect(HyperlitePullRequestRowLayout.deletionsColumnWidth >= 48,
               "removed column should fit a six-digit signed count")
        expect(
            HyperlitePullRequestRowLayout.commentsColumnWidth >=
                layout.reviewFeedbackColumnWidth,
            "comments column should keep the reserved feedback width"
        )
        expect(HyperlitePullRequestRowLayout.ageColumnWidth >= 28,
               "age column should fit four-character labels")
        expect(HyperlitePullRequestRowLayout.failedPipelineColumnWidth >= 56,
               "pipeline column should reserve a short name without shifting counts")
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
        expect(spoken.contains("2 unresolved review threads"),
               "the row should name the comments-column state")

        var pendingGlance = HyperlitePullRequestGlance.empty
        pendingGlance.ciState = "PENDING"
        let pendingSpoken = HyperlitePullRequestRowContent.accessibilityLabel(
            for: row(glance: pendingGlance, threads: 0),
            reviewStatus: .unreviewed
        )
        expect(pendingSpoken.contains("CI pending"),
               "a pending comments column should be spoken")
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
