import Foundation

enum HyperliteDashboardListTests {
    @MainActor
    static func run() throws {
        testPullRequestFilteringAndSorting()
        testProjectFilteringAndSorting()
        try testPersistentReorderAndCollapseState()
    }

    private static func testPullRequestFilteringAndSorting() {
        let rows = pullRequestRows()
        var filter = HyperlitePullRequestFilter()
        filter.query = "brace"
        expect(present(rows, filter: filter).map(\.number) == [12],
               "PR text filtering should match titles case-insensitively")
        filter.query = "  brace\n"
        expect(present(rows, filter: filter).map(\.number) == [12],
               "PR text filtering should ignore surrounding whitespace")
        filter.query = " \n "
        expect(!filter.isActive && present(rows, filter: filter).count == rows.count,
               "whitespace-only PR queries should remain inactive")

        filter = HyperlitePullRequestFilter()
        filter.repository = "owner/two"
        filter.state = .ready
        expect(present(rows, filter: filter).map(\.number) == [8],
               "repository and ready filters should compose")

        filter = HyperlitePullRequestFilter()
        filter.review = .attention
        expect(present(rows, filter: filter).map(\.number) == [12],
               "review filtering should retain unresolved feedback")
        filter.review = .clear
        expect(Set(present(rows, filter: filter).map(\.number)) == [8],
               "clear review filtering should require a confirmed zero")
        filter.review = .unavailable
        expect(Set(present(rows, filter: filter).map(\.number)) == [3],
               "unavailable feedback should stay distinct from clear")

        filter = HyperlitePullRequestFilter()
        filter.data = .cached
        expect(present(rows, filter: filter).map(\.number) == [3],
               "data filtering should distinguish cached rows")

        var availabilityFilter = HyperlitePullRequestFilter()
        availabilityFilter.query = "offline"
        availabilityFilter.data = .unavailable
        expect(HyperliteDashboardListPresentation.availability(
            availabilityRows(), filter: availabilityFilter
        ).map(\.name) == ["offline"],
        "availability filtering should compose identity and unavailable status")
        availabilityFilter.state = .ready
        expect(HyperliteDashboardListPresentation.availability(
            availabilityRows(), filter: availabilityFilter
        ).isEmpty,
        "PR-only state filters should exclude availability rows")

        expect(present(rows, sort: .repository).map(\.number) == [12, 3, 8],
               "repository sorting should be deterministic")
        expect(present(caseVariantPullRequestRows(), sort: .repository).map(\.id) ==
            ["newest", "middle", "oldest"],
            "repository sorting should apply tie-breakers to case variants")
        expect(present(rows, sort: .review).map(\.number) == [12, 8, 3],
               "review sorting should rank attention before clear and unavailable")
        expect(present(rows, sort: .state).map(\.number) == [8, 3, 12],
               "state sorting should put ready rows before drafts")
        expect(present(rows, sort: .number).map(\.number) == [12, 8, 3],
               "number sorting should be descending")
        expect(present(rows, sort: .custom, order: [rows[2].id, rows[0].id])
            .map(\.number) == [3, 8, 12],
            "new PR identities should lead stored custom order")
    }

    private static func testProjectFilteringAndSorting() {
        let projects = projectRows()
        let counts = [projects[0].id: 1, projects[1].id: 3]
        var filter = HyperliteProjectFilter()
        filter.query = "gh-2"
        let branchMatch = present(projects, counts: counts, filter: filter)
        expect(branchMatch.map(\.name) == ["zeta"] &&
            branchMatch[0].lanes.map(\.branch) == ["GH-2"],
            "project filtering should preserve the parent and matching lane")
        filter.query = "  gh-2\n"
        expect(present(projects, counts: counts, filter: filter).map(\.name) == ["zeta"],
               "project filtering should ignore surrounding whitespace")
        filter.query = " \n "
        expect(!filter.isActive &&
            present(projects, counts: counts, filter: filter).count == projects.count,
            "whitespace-only project queries should remain inactive")

        filter = HyperliteProjectFilter()
        filter.lane = .worktree
        let worktrees = present(projects, counts: counts, filter: filter)
        expect(worktrees.map(\.name) == ["zeta"] && worktrees[0].lanes.count == 2,
               "worktree filtering should omit projects without active worktrees")

        filter = HyperliteProjectFilter()
        filter.activity = .pullRequests
        expect(present(projects, counts: counts, filter: filter).count == 2,
               "open-PR filtering should use the loaded PR projection")

        expect(present(projects, counts: counts, sort: .name).map(\.name) == ["alpha", "zeta"],
               "project name sorting should be alphabetical")
        expect(present(projects, counts: counts, sort: .worktrees).map(\.name) == ["zeta", "alpha"],
               "worktree sorting should rank active lanes first")
        filter = HyperliteProjectFilter()
        filter.lane = .branch
        expect(present(projects, counts: counts, filter: filter, sort: .worktrees)
            .map(\.name) == ["zeta", "alpha"],
            "worktree sorting should retain source counts when lane filters narrow rows")
        expect(present(projects, counts: counts, sort: .pullRequests).map(\.name) == ["alpha", "zeta"],
               "open-PR sorting should use current loaded counts")
        expect(present(projects, counts: counts, sort: .custom,
                       order: [projects[1].id, "stale"]).map(\.name) == ["alpha", "zeta"],
               "new projects should append after known custom identities")
    }

    @MainActor
    private static func testPersistentReorderAndCollapseState() throws {
        let suite = "HyperliteDashboardListTests.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suite), "test defaults should open")
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = HyperliteDashboardListState(defaults: defaults)
        state.setPullRequestSort(.repository)
        state.beginPullRequestReordering(currentIDs: ["one", "two", "three"])
        state.movePullRequest("one", over: "three")
        expect(state.orderedPullRequestIDs(["one", "two", "three"]) == ["two", "three", "one"],
               "forward PR drag should move beyond the crossed target")
        state.finishPullRequestReordering(commit: false)

        state.beginPullRequestReordering(currentIDs: ["one", "two", "three"])
        state.movePullRequest("three", over: "one")
        expect(state.orderedPullRequestIDs(["one", "two", "three"]) == ["three", "one", "two"],
               "PR reorder draft should move without persistence")
        state.finishPullRequestReordering(commit: false)
        expect(state.pullRequestSort == .repository &&
            state.orderedPullRequestIDs(["one", "two", "three"]) == ["one", "two", "three"],
            "cancel should restore prior PR sort and order")

        state.beginPullRequestReordering(currentIDs: ["one", "two", "three"])
        state.movePullRequest("three", by: -2)
        state.finishPullRequestReordering(commit: true)
        expect(state.pullRequestSort == .custom &&
            state.orderedPullRequestIDs(["new", "one", "two", "three"]) ==
                ["new", "three", "one", "two"],
            "committed PR order should persist and put new PRs first")

        state.beginProjectReordering(currentIDs: ["alpha", "beta", "gamma"])
        state.moveProject("alpha", over: "gamma")
        expect(state.orderedProjectIDs(["alpha", "beta", "gamma"]) ==
            ["beta", "gamma", "alpha"],
            "forward project drag should move beyond the crossed target")
        state.finishProjectReordering(commit: false)

        state.beginProjectReordering(currentIDs: ["alpha", "beta"])
        state.moveProject("beta", over: "alpha")
        state.finishProjectReordering(commit: true)
        state.toggleProject("beta")
        expect(state.isProjectCollapsed("beta", whileFiltering: false),
               "project collapse should persist as presentation state")
        expect(!state.isProjectCollapsed("beta", whileFiltering: true),
               "active filtering should temporarily expand collapsed projects")

        let restored = HyperliteDashboardListState(defaults: defaults)
        expect(restored.pullRequestSort == .custom &&
            restored.orderedPullRequestIDs(["one", "two", "three"]) == ["three", "one", "two"],
            "PR custom order should survive state re-creation")
        expect(restored.projectSort == .custom &&
            restored.orderedProjectIDs(["alpha", "beta", "new"]) == ["beta", "alpha", "new"],
            "project custom order should survive with new projects appended")
        expect(restored.isProjectCollapsed("beta", whileFiltering: false),
               "project collapse should survive state re-creation")
    }

    private static func present(
        _ rows: [HyperlitePullRequestRow],
        filter: HyperlitePullRequestFilter = HyperlitePullRequestFilter(),
        sort: HyperlitePullRequestSort = .recent,
        order: [String] = []
    ) -> [HyperlitePullRequestRow] {
        HyperliteDashboardListPresentation.pullRequests(
            rows, filter: filter, sort: sort, customOrder: order
        )
    }

    private static func present(
        _ projects: [HyperliteProjectLocation],
        counts: [String: Int],
        filter: HyperliteProjectFilter = HyperliteProjectFilter(),
        sort: HyperliteProjectSort = .configured,
        order: [String] = []
    ) -> [HyperliteProjectLocation] {
        HyperliteDashboardListPresentation.projects(
            projects, pullRequestCounts: counts, filter: filter,
            sort: sort, customOrder: order
        )
    }

    private static func pullRequestRows() -> [HyperlitePullRequestRow] {
        let now = Date(timeIntervalSince1970: 1_785_850_000)
        return [
            HyperlitePullRequestRow(id: "one#12", reviewID: "owner/one#12",
                repository: "owner/one", status: .current, number: 12,
                title: "Bump brace expansion", url: nil, headRefOID: "head-12", isDraft: true,
                hasMergeConflict: false, unresolvedReviewThreads: 2, updatedAt: now
            ),
            HyperlitePullRequestRow(id: "one#3", reviewID: "owner/one#3",
                repository: "owner/one", status: .cached, number: 3,
                title: "Cached repair", url: nil, headRefOID: "head-3", isDraft: false,
                hasMergeConflict: false, unresolvedReviewThreads: nil, updatedAt: now.addingTimeInterval(-20)
            ),
            HyperlitePullRequestRow(id: "two#8", reviewID: "owner/two#8",
                repository: "owner/two", status: .current, number: 8,
                title: "Ready change", url: nil, headRefOID: "head-8", isDraft: false,
                hasMergeConflict: false, unresolvedReviewThreads: 0, updatedAt: now.addingTimeInterval(-10)
            ),
        ]
    }

    private static func caseVariantPullRequestRows() -> [HyperlitePullRequestRow] {
        let now = Date(timeIntervalSince1970: 1_785_850_000)
        return [
            HyperlitePullRequestRow(id: "oldest", reviewID: "owner/repo#1",
                repository: "Owner/Repo", status: .current, number: 1,
                title: "Oldest", url: nil, headRefOID: "head-1", isDraft: false,
                hasMergeConflict: false, unresolvedReviewThreads: 0, updatedAt: now.addingTimeInterval(-20)
            ),
            HyperlitePullRequestRow(id: "middle", reviewID: "owner/repo#2",
                repository: "owner/repo", status: .current, number: 2,
                title: "Middle", url: nil, headRefOID: "head-2", isDraft: false,
                hasMergeConflict: false, unresolvedReviewThreads: 0, updatedAt: now.addingTimeInterval(-10)
            ),
            HyperlitePullRequestRow(id: "newest", reviewID: "owner/repo#3",
                repository: "Owner/Repo", status: .current, number: 3,
                title: "Newest", url: nil, headRefOID: "head-3", isDraft: false,
                hasMergeConflict: false, unresolvedReviewThreads: 0, updatedAt: now
            ),
        ]
    }

    private static func availabilityRows() -> [HyperliteProjectPullRequests] {
        [
            HyperliteProjectPullRequests(
                id: "cached", name: "cached", path: "/repo/cached",
                repository: "owner/cached", status: .cached, message: "using cache",
                checkedAt: nil, observedAt: nil, pullRequests: []
            ),
            HyperliteProjectPullRequests(
                id: "offline", name: "offline", path: "/repo/offline",
                repository: nil, status: .unavailable, message: "GitHub unavailable",
                checkedAt: nil, observedAt: nil, pullRequests: []
            ),
        ]
    }

    private static func projectRows() -> [HyperliteProjectLocation] {
        let primary = { (name: String) in
            HyperliteProjectLane(
                id: "/repo/\(name)", branch: "main", path: "/repo/\(name)",
                primary: true, detached: false
            )
        }
        return [
            HyperliteProjectLocation(
                id: "/repo/zeta", name: "zeta", path: "/repo/zeta", repository: "owner/zeta",
                lanes: [
                    primary("zeta"),
                    HyperliteProjectLane(id: "/wt/zeta/GH-2", branch: "GH-2",
                                         path: "/wt/zeta/GH-2", primary: false, detached: false),
                    HyperliteProjectLane(id: "/wt/zeta/GH-7", branch: "GH-7",
                                         path: "/wt/zeta/GH-7", primary: false, detached: false),
                ]
            ),
            HyperliteProjectLocation(
                id: "/repo/alpha", name: "alpha", path: "/repo/alpha",
                repository: "owner/alpha", lanes: [primary("alpha")]
            ),
        ]
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
