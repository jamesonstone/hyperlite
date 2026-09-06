import Foundation

enum HyperlitePullRequestHoverTests {
    static func run() {
        testHoverShowsSummaryAndConflictNextStep()
        testHoverOmitsDenseMetadata()
        testHoverPrefersReviewWaitWhenClear()
        testHoverDecodesSummary()
    }

    private static func testHoverShowsSummaryAndConflictNextStep() {
        var glance = HyperlitePullRequestGlance.empty
        glance.summary = "keep hover from opening GitHub."
        glance.ciState = "SUCCESS"
        glance.reviewDecision = "REVIEW_REQUIRED"
        glance.authorLogin = "jameson"
        glance.commentCount = 4
        let card = HyperlitePullRequestHoverPresentation.snapshot(
            row: row(glance: glance, conflict: true, threads: 2),
            reviewStatus: .unreviewed
        )
        expect(card.summary == "keep hover from opening GitHub.",
               "hover should show the derived what-and-why")
        expect(card.nextStep == "fix merge conflicts" && card.nextStepNeedsAttention,
               "conflicts should be the next step")
        expect(card.status == "CI success",
               "CI should remain a quiet supporting line when it is not the next step")
        expect(card.identity == "owner/one #12" && card.title == "Ship hover",
               "hover should keep compact identity")
        expect(card.meta.contains("ready"), "hover should keep draft/ready in the meta line")
    }

    private static func testHoverOmitsDenseMetadata() {
        var glance = HyperlitePullRequestGlance.empty
        glance.authorLogin = "jameson"
        glance.headRefName = "GH-72"
        glance.labels = ["ready"]
        glance.additions = 12
        glance.commentCount = 4
        glance.ciState = "SUCCESS"
        let card = HyperlitePullRequestHoverPresentation.snapshot(
            row: row(glance: glance, conflict: true, threads: 0, oid: "abcdef1"),
            reviewStatus: .unreviewed
        )
        let spoken = card.accessibilityLabel
        expect(!spoken.contains("jameson") && !spoken.contains("GH-72"),
               "hover should not dump author or branch")
        expect(!spoken.contains("+12") && !spoken.contains("comments"),
               "hover should not dump diffstat or comment count")
        expect(!spoken.contains("abcdef1") && !spoken.contains("github.com"),
               "hover should not dump SHA or URL")
    }

    private static func testHoverPrefersReviewWaitWhenClear() {
        var glance = HyperlitePullRequestGlance.empty
        glance.ciState = "SUCCESS"
        glance.reviewDecision = "REVIEW_REQUIRED"
        glance.reviewRequests = ["octocat"]
        let card = HyperlitePullRequestHoverPresentation.snapshot(
            row: row(glance: glance, conflict: false, threads: 0),
            reviewStatus: .unreviewed
        )
        expect(card.nextStep == "waiting on octocat" && !card.nextStepNeedsAttention,
               "clear PRs should name who is next")
        expect(card.status == "CI success", "supporting CI should remain when review is next")
    }

    private static func testHoverDecodesSummary() {
        let data = Data("""
        {
          "id": "owner/one#12",
          "number": 12,
          "title": "Ship hover",
          "url": "https://github.com/owner/one/pull/12",
          "head_ref_name": "GH-12",
          "head_ref_oid": "abcdef1",
          "is_draft": false,
          "has_merge_conflict": false,
          "updated_at": "2026-09-05T12:00:00Z",
          "summary": "keep hover readable"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let pullRequest = try decoder.decode(HyperliteProjectPullRequest.self, from: data)
            expect(pullRequest.glance.summary == "keep hover readable",
                   "scan JSON should decode the derived summary")
        } catch {
            expect(false, "summary JSON should decode")
        }
    }

    private static func row(
        glance: HyperlitePullRequestGlance,
        conflict: Bool,
        threads: Int?,
        oid: String = "abcdef1"
    ) -> HyperlitePullRequestRow {
        HyperlitePullRequestRow(
            id: "one#12", reviewID: "owner/one#12", repository: "owner/one",
            status: .current, number: 12, title: "Ship hover",
            url: URL(string: "https://github.com/owner/one/pull/12"),
            headRefOID: oid, isDraft: false, hasMergeConflict: conflict,
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
