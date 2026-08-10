import Foundation

enum HyperlitePullRequestReviewMarkerTests {
    @MainActor
    static func run() throws {
        try testRevisionAwarePersistence()
        try testAuthoritativePruningAndBulkClear()
        try testLegacyHeadCommitRefresh()
        testLocalReviewFiltering()
    }

    private static func testLegacyHeadCommitRefresh() throws {
        let data = Data("""
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
              "id": "owner/one#1",
              "number": 1,
              "title": "Legacy",
              "url": "https://github.com/owner/one/pull/1",
              "head_ref_name": "GH-1",
              "is_draft": false,
              "unresolved_review_threads": 0,
              "updated_at": "2026-07-29T16:04:00Z"
            }]
          }],
          "errors": [],
          "warnings": []
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scan = try decoder.decode(HyperliteProjectPullRequestScan.self, from: data)
        let checkedAt = try require(scan.checkedAt, "legacy checked time should decode")
        expect(scan.projects[0].pullRequests[0].headRefOID.isEmpty,
               "a missing legacy head commit should decode as empty")
        expect(
            HyperlitePullRequestPresentation.isStale(
                scan: scan, now: checkedAt
            ),
            "a legacy current row should trigger head-commit hydration"
        )
        let cachedScan = Self.scan(projects: [Self.project(
            repository: "owner/one",
            status: .cached,
            pullRequests: scan.projects[0].pullRequests
        )])
        let cachedCheckedAt = try require(
            cachedScan.checkedAt,
            "cached checked time should exist"
        )
        expect(
            !HyperlitePullRequestPresentation.isStale(
                scan: cachedScan, now: cachedCheckedAt
            ),
            "failed head-commit hydration should retain the five-minute retry floor"
        )
    }

    @MainActor
    private static func testRevisionAwarePersistence() throws {
        let suite = "HyperlitePullRequestReviewMarkerTests.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suite), "test defaults should open")
        defer { defaults.removePersistentDomain(forName: suite) }
        let markedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let original = row(reviewID: "owner/one#1", repository: "owner/one", head: "head-1")

        let state = HyperliteDashboardListState(defaults: defaults)
        state.togglePullRequestReviewed(original, now: markedAt)
        expect(state.pullRequestReviewStatus(for: original) == .reviewed,
               "a checked PR should be reviewed for its observed head")
        expect(state.pullRequestReviewMarks[original.reviewID]?.markedAt == markedAt,
               "the local review mark should retain its mark time")

        let restored = HyperliteDashboardListState(defaults: defaults)
        expect(restored.pullRequestReviewStatus(for: original) == .reviewed,
               "review marks should survive state re-creation")
        let changed = row(
            reviewID: original.reviewID,
            repository: original.repository,
            head: "head-2"
        )
        expect(restored.pullRequestReviewStatus(for: changed) == .stale,
               "a current head change should make the prior review mark stale")

        let cached = row(
            reviewID: original.reviewID,
            repository: original.repository,
            status: .cached,
            head: "head-2"
        )
        expect(restored.pullRequestReviewStatus(for: cached) == .reviewed,
               "cached evidence should not invalidate a local review mark")

        restored.togglePullRequestReviewed(cached)
        expect(restored.pullRequestReviewStatus(for: cached) == .unreviewed,
               "a cached reviewed row should remain clearable")
        restored.togglePullRequestReviewed(cached)
        expect(restored.pullRequestReviewMarkCount == 0,
               "cached evidence should not create a review mark")
        let afterCachedAttempt = HyperliteDashboardListState(defaults: defaults)
        expect(afterCachedAttempt.pullRequestReviewMarkCount == 0,
               "a cached unreviewed row should not persist a review mark")

        afterCachedAttempt.togglePullRequestReviewed(original, now: markedAt)
        afterCachedAttempt.togglePullRequestReviewed(
            changed,
            now: markedAt.addingTimeInterval(60)
        )
        expect(afterCachedAttempt.pullRequestReviewStatus(for: changed) == .reviewed &&
            afterCachedAttempt.pullRequestReviewMarks[changed.reviewID]?.headRefOID == "head-2",
            "checking a stale PR should bind the mark to its new head")
        afterCachedAttempt.togglePullRequestReviewed(changed)
        expect(afterCachedAttempt.pullRequestReviewStatus(for: changed) == .unreviewed,
               "checking a reviewed PR should clear its mark")

        let missingHead = row(
            reviewID: "owner/one#2",
            repository: "owner/one",
            head: ""
        )
        afterCachedAttempt.togglePullRequestReviewed(missingHead)
        expect(afterCachedAttempt.pullRequestReviewMarkCount == 0,
               "a PR without a head commit should not acquire a review mark")
    }

    @MainActor
    private static func testAuthoritativePruningAndBulkClear() throws {
        let suite = "HyperlitePullRequestReviewPruningTests.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suite), "test defaults should open")
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = HyperliteDashboardListState(defaults: defaults)
        let current = row(reviewID: "owner/one#1", repository: "Owner/One", head: "head-1")
        let cached = row(reviewID: "owner/two#2", repository: "owner/two", head: "head-2")
        state.togglePullRequestReviewed(current)
        state.togglePullRequestReviewed(cached)

        state.reconcilePullRequestReviewMarks(scan: scan(projects: [
            project(repository: "owner/one", status: .current, pullRequests: []),
            project(repository: "owner/two", status: .cached, pullRequests: []),
        ]))
        expect(state.pullRequestReviewMarks[current.reviewID] == nil,
               "current repository evidence should prune a closed PR mark")
        expect(state.pullRequestReviewMarks[cached.reviewID] != nil,
               "cached repository evidence should preserve an absent PR mark")

        state.clearPullRequestReviewMarks()
        expect(state.pullRequestReviewMarkCount == 0,
               "bulk clear should remove every retained review mark")
        let restored = HyperliteDashboardListState(defaults: defaults)
        expect(restored.pullRequestReviewMarkCount == 0,
               "bulk clear should persist across state re-creation")
    }

    private static func testLocalReviewFiltering() {
        let reviewed = row(reviewID: "owner/one#1", repository: "owner/one", head: "head-1")
        let stale = row(reviewID: "owner/one#2", repository: "owner/one", head: "head-2")
        let unreviewed = row(reviewID: "owner/two#3", repository: "owner/two", head: "head-3")
        let rows = [reviewed, stale, unreviewed]
        let statuses: [String: HyperlitePullRequestReviewStatus] = [
            reviewed.reviewID: .reviewed,
            stale.reviewID: .stale,
        ]
        var filter = HyperlitePullRequestFilter()
        filter.localReview = .reviewed
        expect(present(rows, filter: filter, statuses: statuses).map(\.reviewID) ==
            [reviewed.reviewID],
            "reviewed filtering should retain only active local marks")
        filter.localReview = .stale
        expect(present(rows, filter: filter, statuses: statuses).map(\.reviewID) ==
            [stale.reviewID],
            "stale filtering should retain only invalidated local marks")
        filter.localReview = .unreviewed
        expect(present(rows, filter: filter, statuses: statuses).map(\.reviewID) ==
            [unreviewed.reviewID],
            "unreviewed filtering should retain rows without local marks")
        expect(filter.isActive, "a local review filter should activate filtered counts")

        let availability = HyperliteProjectPullRequests(
            id: "/offline", name: "offline", path: "/offline", repository: nil,
            status: .unavailable, message: "offline", checkedAt: nil, observedAt: nil,
            pullRequests: []
        )
        expect(HyperliteDashboardListPresentation.availability(
            [availability], filter: filter
        ).isEmpty,
        "a PR-only local review filter should exclude availability rows")
    }

    private static func present(
        _ rows: [HyperlitePullRequestRow],
        filter: HyperlitePullRequestFilter,
        statuses: [String: HyperlitePullRequestReviewStatus]
    ) -> [HyperlitePullRequestRow] {
        HyperliteDashboardListPresentation.pullRequests(
            rows,
            filter: filter,
            sort: .recent,
            customOrder: [],
            reviewStatuses: statuses
        )
    }

    private static func row(
        reviewID: String,
        repository: String,
        status: HyperliteProjectPullRequestStatus = .current,
        head: String
    ) -> HyperlitePullRequestRow {
        HyperlitePullRequestRow(
            id: reviewID,
            reviewID: reviewID,
            repository: repository,
            status: status,
            number: 1,
            title: reviewID,
            url: nil,
            headRefOID: head,
            isDraft: false,
            unresolvedReviewThreads: 0,
            updatedAt: Date(timeIntervalSince1970: 1_786_000_000)
        )
    }

    private static func project(
        repository: String,
        status: HyperliteProjectPullRequestStatus,
        pullRequests: [HyperliteProjectPullRequest]
    ) -> HyperliteProjectPullRequests {
        HyperliteProjectPullRequests(
            id: "/\(repository)", name: repository, path: "/\(repository)",
            repository: repository, status: status, message: nil,
            checkedAt: Date(), observedAt: Date(), pullRequests: pullRequests
        )
    }

    private static func scan(
        projects: [HyperliteProjectPullRequests]
    ) -> HyperliteProjectPullRequestScan {
        HyperliteProjectPullRequestScan(
            schemaVersion: 1, generatedAt: Date(), checkedAt: Date(), observedAt: Date(),
            rateLimit: nil, refreshIntervalSeconds: 300, projects: projects,
            errors: [], warnings: []
        )
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

    private struct TestFailure: Error { let message: String }
}
