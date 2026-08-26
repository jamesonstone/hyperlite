import Foundation

enum HyperliteOpenPRControlsTests {
    static func run() throws {
        try testLegacyCacheOmitsMergeConflict()
        try testMergeConflictDecodingAndPresentation()
        testHideDraftFiltering()
        testRowLayoutReservesConflictColumn()
    }

    private static func testLegacyCacheOmitsMergeConflict() throws {
        let scan = try decodeScan(legacyConflictJSON)
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        expect(rows.count == 1 && !rows[0].hasMergeConflict,
               "legacy cache without has_merge_conflict should decode as no conflict")
        expect(
            HyperlitePullRequestPresentation.mergeConflictAccessibilityLabel(
                hasMergeConflict: false
            ) == nil,
            "unconfirmed conflicts should stay silent to accessibility"
        )
    }

    private static func testMergeConflictDecodingAndPresentation() throws {
        let scan = try decodeScan(conflictingJSON)
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        expect(rows.count == 1 && rows[0].hasMergeConflict,
               "confirmed GitHub conflicts should decode onto the row")
        expect(
            HyperlitePullRequestPresentation.mergeConflictAccessibilityLabel(
                hasMergeConflict: true
            ) == "has merge conflicts",
            "confirmed conflicts should be named for accessibility"
        )
    }

    private static func testHideDraftFiltering() {
        let rows = [
            row(id: "ready", number: 8, isDraft: false),
            row(id: "draft", number: 12, isDraft: true),
        ]
        var filter = HyperlitePullRequestFilter()
        expect(!filter.isActive && !filter.popoverIsActive,
               "hide-drafts should start inactive")
        filter.hideDrafts = true
        expect(filter.isActive && !filter.popoverIsActive,
               "hide-drafts should count as an active list filter without opening the popover")
        expect(
            HyperliteDashboardListPresentation.pullRequests(
                rows, filter: filter, sort: .recent, customOrder: []
            ).map(\.number) == [8],
            "hide-drafts should exclude draft rows and keep ready rows"
        )
        filter.state = .draft
        expect(
            HyperliteDashboardListPresentation.pullRequests(
                rows, filter: filter, sort: .recent, customOrder: []
            ).isEmpty,
            "hide-drafts should compose with a draft-only state filter as empty"
        )
        filter = HyperlitePullRequestFilter()
        filter.hideDrafts = true
        expect(
            HyperliteDashboardListPresentation.availability(
                availabilityRows(), filter: filter
            ).isEmpty,
            "hide-drafts should hide availability rows like other PR-only filters"
        )
    }

    private static func testRowLayoutReservesConflictColumn() {
        let layout = HyperlitePullRequestPanelRow.layout
        expect(layout.mergeConflictColumnWidth >= 14,
               "conflict column should reserve space for the attention icon")
        expect(
            layout.availabilityMetadataColumnWidth >=
                42 + 42 + layout.mergeConflictColumnWidth +
                layout.reviewFeedbackColumnWidth,
            "availability metadata should stay aligned after the conflict column"
        )
    }

    private static func decodeScan(_ json: String) throws -> HyperliteProjectPullRequestScan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            HyperliteProjectPullRequestScan.self,
            from: Data(json.utf8)
        )
    }

    private static func row(
        id: String,
        number: Int,
        isDraft: Bool
    ) -> HyperlitePullRequestRow {
        HyperlitePullRequestRow(
            id: id, reviewID: id, repository: "owner/one", status: .current,
            number: number, title: id, url: nil, headRefOID: "head-\(number)",
            isDraft: isDraft, hasMergeConflict: false, unresolvedReviewThreads: 0,
            updatedAt: Date(timeIntervalSince1970: 1_785_850_000)
        )
    }

    private static func availabilityRows() -> [HyperliteProjectPullRequests] {
        [
            HyperliteProjectPullRequests(
                id: "offline", name: "offline", path: "/repo/offline",
                repository: nil, status: .unavailable, message: "GitHub unavailable",
                checkedAt: nil, observedAt: nil, pullRequests: []
            ),
        ]
    }

    private static let conflictingJSON = """
        {
          "schema_version": 1,
          "generated_at": "2026-07-29T16:06:00Z",
          "checked_at": "2026-07-29T16:05:00Z",
          "observed_at": "2026-07-29T16:05:00Z",
          "refresh_interval_seconds": 300,
          "projects": [{
            "id": "/repo/one",
            "name": "one",
            "path": "/repo/one",
            "repository": "owner/one",
            "status": "current",
            "checked_at": "2026-07-29T16:05:00Z",
            "observed_at": "2026-07-29T16:05:00Z",
            "pull_requests": [{
              "id": "owner/one#9",
              "number": 9,
              "title": "Ready change",
              "url": "https://github.com/owner/one/pull/9",
              "head_ref_name": "GH-9",
              "head_ref_oid": "head-9",
              "is_draft": false,
              "has_merge_conflict": true,
              "unresolved_review_threads": 0,
              "updated_at": "2026-07-29T16:04:00Z"
            }]
          }],
          "errors": [],
          "warnings": []
        }
        """

    private static let legacyConflictJSON = """
        {
          "schema_version": 1,
          "generated_at": "2026-07-29T16:06:00Z",
          "checked_at": "2026-07-29T16:05:00Z",
          "observed_at": "2026-07-29T16:05:00Z",
          "refresh_interval_seconds": 300,
          "projects": [{
            "id": "/repo/one",
            "name": "one",
            "path": "/repo/one",
            "repository": "owner/one",
            "status": "cached",
            "message": "network unavailable",
            "checked_at": "2026-07-29T16:05:00Z",
            "observed_at": "2026-07-29T16:05:00Z",
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
          }],
          "errors": [],
          "warnings": []
        }
        """

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
