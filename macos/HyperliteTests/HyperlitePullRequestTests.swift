import Foundation

enum HyperlitePullRequestTests {
    static func run() throws {
        let scan = try testSchemaDecodingAndPresentation()
        testFiveMinuteFreshnessFloor(scan: scan)
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
                "is_draft": false,
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
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        expect(rows.map(\.number) == [9, 7], "rows should be recent-first")
        expect(rows[0].repository == "owner/two" && !rows[0].isDraft,
               "ready pull request metadata should decode")
        expect(scan.projects[1].pullRequests[0].headRefName == "GH-9",
               "head branch should decode for project-lane projection")
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
