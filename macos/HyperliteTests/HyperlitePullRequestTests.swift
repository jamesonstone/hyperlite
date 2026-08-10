import Foundation

enum HyperlitePullRequestTests {
    static func run() throws {
        let scan = try testSchemaDecodingAndPresentation()
        testFiveMinuteFreshnessFloor(scan: scan)
        testLegacyFeedbackRefresh()
        testFreshnessTimestamp(scan: scan)
        testReviewFeedbackPresentation()
        testRowLayoutPrioritizesRepositoryIdentity()
    }

    private static func testSchemaDecodingAndPresentation() throws
        -> HyperliteProjectPullRequestScan
    {
        let data = Data("""
        {
          "schema_version": 1,
          "generated_at": "2026-07-29T16:06:00Z",
          "checked_at": "2026-07-29T16:05:00Z",
          "observed_at": "2026-07-29T15:55:00Z",
          "rate_limit": {
            "limit": 5000,
            "used": 1551,
            "remaining": 3449,
            "reset_at": "2026-07-29T17:00:00Z",
            "cost": 4,
            "node_count": 12,
            "observed_at": "2026-07-29T16:05:00Z",
            "burn_rate": {
              "points_per_hour": 2400,
              "sample_seconds": 300,
              "projected_exhaustion_at": "2026-07-29T17:31:13Z"
            }
          },
          "refresh_interval_seconds": 300,
          "projects": [
            {
              "id": "/repo/one",
              "name": "one",
              "path": "/repo/one",
              "repository": "owner/one",
              "status": "cached",
              "message": "network unavailable",
              "checked_at": "2026-07-29T16:05:00Z",
              "observed_at": "2026-07-29T15:55:00Z",
              "pull_requests": [{
                "id": "owner/one#7",
                "number": 7,
                "title": "Draft change",
                "url": "https://github.com/owner/one/pull/7",
                "head_ref_name": "GH-7",
                "head_ref_oid": "head-7",
                "is_draft": true,
                "updated_at": "2026-07-29T15:58:00Z"
              }]
            },
            {
              "id": "/repo/two",
              "name": "two",
              "path": "/repo/two",
              "repository": "owner/two",
              "status": "current",
              "checked_at": "2026-07-29T16:05:00Z",
              "observed_at": "2026-07-29T16:05:00Z",
              "pull_requests": [{
                "id": "owner/two#9",
                "number": 9,
                "title": "Ready change",
                "url": "https://github.com/owner/two/pull/9",
                "head_ref_name": "GH-9",
                "head_ref_oid": "head-9",
                "is_draft": false,
                "unresolved_review_threads": 3,
                "updated_at": "2026-07-29T16:04:00Z"
              }]
            },
            {
              "id": "/repo/local",
              "name": "local",
              "path": "/repo/local",
              "status": "unavailable",
              "message": "no GitHub remote found",
              "pull_requests": []
            }
          ],
          "errors": [],
          "warnings": []
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scan = try decoder.decode(HyperliteProjectPullRequestScan.self, from: data)
        expect(
            scan.rateLimit?.used == 1551 && scan.rateLimit?.remaining == 3449 &&
                scan.rateLimit?.cost == 4 && scan.rateLimit?.nodeCount == 12 &&
                scan.rateLimit?.burnRate?.pointsPerHour == 2400 &&
                scan.rateLimit?.burnRate?.sampleSeconds == 300,
            "complete GraphQL rate-limit metadata should decode"
        )
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        expect(rows.map(\.number) == [9, 7], "rows should be recent-first")
        expect(rows[0].repository == "owner/two" && !rows[0].isDraft,
               "ready pull request metadata should decode")
        expect(rows[0].unresolvedReviewThreads == 3,
               "actionable review feedback should decode")
        expect(rows[1].unresolvedReviewThreads == nil,
               "legacy cached feedback should remain explicitly unavailable")
        expect(scan.projects[1].pullRequests[0].headRefName == "GH-9",
               "head branch should decode for project-lane projection")
        expect(rows[0].headRefOID == "head-9",
               "head commit should decode for revision-aware review markers")
        expect(rows[1].status == .cached && rows[1].isDraft,
               "cached draft metadata should remain visible")
        expect(rows[0].url?.absoluteString == "https://github.com/owner/two/pull/9",
               "row URL should remain directly actionable")
        expect(
            HyperlitePullRequestPresentation.availability(scan: scan).map(\.name) ==
                ["one", "local"],
            "cached and unavailable projects should remain distinguishable"
        )
        return scan
    }

    private static func testFiveMinuteFreshnessFloor(
        scan: HyperliteProjectPullRequestScan
    ) {
        let checkedAt = try! require(scan.checkedAt, "checked time should decode")
        expect(
            !HyperlitePullRequestPresentation.isStale(
                scan: scan,
                now: checkedAt.addingTimeInterval(299)
            ),
            "automatic refresh should not run inside five minutes"
        )
        expect(
            HyperlitePullRequestPresentation.isStale(
                scan: scan,
                now: checkedAt.addingTimeInterval(300)
            ),
            "automatic refresh should become eligible at five minutes"
        )
        let tooShort = HyperliteProjectPullRequestScan(
            schemaVersion: scan.schemaVersion,
            generatedAt: scan.generatedAt,
            checkedAt: checkedAt,
            observedAt: scan.observedAt,
            rateLimit: scan.rateLimit,
            refreshIntervalSeconds: 30,
            projects: scan.projects,
            errors: [],
            warnings: []
        )
        expect(
            !HyperlitePullRequestPresentation.isStale(
                scan: tooShort,
                now: checkedAt.addingTimeInterval(299)
            ),
            "native freshness should enforce the five-minute floor"
        )
    }

    private static func testFreshnessTimestamp(scan: HyperliteProjectPullRequestScan) {
        expect(
            HyperlitePullRequestPresentation.freshnessLabel(
                observedAt: scan.observedAt,
                timeZone: TimeZone(secondsFromGMT: 0)!
            ) == "Updated 2026-07-29 15:55",
            "freshness should include a date and 24-hour minute timestamp"
        )
        expect(
            HyperlitePullRequestPresentation.freshnessLabel(observedAt: nil) ==
                "GitHub availability limited",
            "missing observations should remain explicit"
        )
    }

    private static func testLegacyFeedbackRefresh() {
        let checkedAt = Date(timeIntervalSince1970: 1_785_340_800)
        let pullRequest = HyperliteProjectPullRequest(
            id: "owner/one#1", number: 1, title: "Legacy",
            url: "https://github.com/owner/one/pull/1",
            headRefName: "GH-1", headRefOID: "head-1", isDraft: false,
            unresolvedReviewThreads: nil, updatedAt: checkedAt
        )
        func scan(status: HyperliteProjectPullRequestStatus)
            -> HyperliteProjectPullRequestScan
        {
            HyperliteProjectPullRequestScan(
                schemaVersion: 1, generatedAt: checkedAt, checkedAt: checkedAt,
                observedAt: checkedAt, rateLimit: nil, refreshIntervalSeconds: 300,
                projects: [HyperliteProjectPullRequests(
                    id: "/repo/one", name: "one", path: "/repo/one",
                    repository: "owner/one", status: status, message: nil,
                    checkedAt: checkedAt, observedAt: checkedAt,
                    pullRequests: [pullRequest]
                )],
                errors: [], warnings: []
            )
        }
        expect(
            HyperlitePullRequestPresentation.isStale(
                scan: scan(status: .current), now: checkedAt
            ),
            "a legacy current row should trigger feedback-count hydration"
        )
        expect(
            !HyperlitePullRequestPresentation.isStale(
                scan: scan(status: .cached), now: checkedAt
            ),
            "a failed legacy hydration should retain the five-minute retry floor"
        )
    }

    private static func testReviewFeedbackPresentation() {
        let unavailable = HyperlitePullRequestPresentation.reviewFeedback(
            unresolvedThreads: nil
        )
        expect(unavailable.text == "?" && !unavailable.needsAttention,
               "unavailable feedback should not masquerade as zero or attention")
        expect(unavailable.accessibilityLabel == "review feedback count unavailable",
               "unavailable feedback should remain explicit to accessibility")

        let none = HyperlitePullRequestPresentation.reviewFeedback(
            unresolvedThreads: 0
        )
        expect(none.text == "—" && !none.needsAttention,
               "a confirmed zero should remain visually quiet")
        expect(none.accessibilityLabel == "no unresolved review threads",
               "a confirmed zero should have a complete accessibility label")

        let one = HyperlitePullRequestPresentation.reviewFeedback(
            unresolvedThreads: 1
        )
        expect(one.text == "1" && one.needsAttention,
               "one unresolved thread should request attention")
        expect(one.accessibilityLabel == "1 unresolved review thread",
               "one unresolved thread should use singular accessibility text")

        let many = HyperlitePullRequestPresentation.reviewFeedback(
            unresolvedThreads: 4
        )
        expect(many.text == "4" && many.needsAttention,
               "multiple unresolved threads should request attention")
        expect(many.accessibilityLabel == "4 unresolved review threads",
               "multiple unresolved threads should use plural accessibility text")
    }

    private static func testRowLayoutPrioritizesRepositoryIdentity() {
        let rowLayouts = [
            ("current", HyperlitePullRequestPanelRow.layout),
            ("availability", HyperlitePullRequestAvailabilityRow.layout),
        ]
        for (rowKind, layout) in rowLayouts {
            expect(
                layout.repositoryColumnWidth >= 180,
                "\(rowKind) row repository column should distinguish common project names"
            )
            expect(
                layout.repositoryLayoutPriority > layout.titleLayoutPriority,
                "\(rowKind) row title should yield space before repository identity"
            )
            expect(
                layout.reviewFeedbackColumnWidth >= 24,
                "\(rowKind) row should reserve an aligned feedback column"
            )
            expect(
                layout.availabilityMetadataColumnWidth > 91,
                "\(rowKind) availability text should align with the widened metadata"
            )
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestFailure(message: message) }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    private struct TestFailure: Error {
        let message: String
    }
}
