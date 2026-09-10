import Foundation

enum HyperlitePullRequestPinningTests {
    static func run() {
        testNewRowsStayUnpinnedUntilDragged()
        testDraggingIntoPinnedFlipsStateAndOrder()
        testKeyboardMoveCrossesThePinBoundary()
        testUnpinnedRowsGroupByRepository()
        testSameProjectDropReordersInsideTheGroup()
        testCrossProjectDropMovesTheGroup()
        testAdjacentDownwardGroupDropMovesTheGroup()
        testKeyboardMoveAtGroupBoundaryMovesTheGroup()
    }

    private static func testNewRowsStayUnpinnedUntilDragged() {
        let sections = HyperlitePullRequestPinning.sections(
            rows: rows(),
            pinnedIDs: [],
            unpinnedIDs: []
        )
        expect(sections.pinned.isEmpty, "new rows should not start pinned")
        expect(sections.unpinned.map(\.id) == ["a", "b", "c"],
               "unpinned rows should keep source order when nothing is stored")
    }

    private static func testDraggingIntoPinnedFlipsStateAndOrder() {
        var pinned: [String] = ["a"]
        var unpinned: [String] = ["b", "c"]
        HyperlitePullRequestPinning.move(
            "c", over: "a", pinned: &pinned, unpinned: &unpinned
        )
        expect(pinned == ["c", "a"], "dropping onto a pinned row should pin at that index")
        expect(unpinned == ["b"], "the dragged row should leave the unpinned list")
        let sections = HyperlitePullRequestPinning.sections(
            rows: rows(), pinnedIDs: pinned, unpinnedIDs: unpinned
        )
        expect(sections.pinned.map(\.id) == ["c", "a"],
               "displayed pinned order should follow the stored pin list")
        expect(sections.unpinned.map(\.id) == ["b"],
               "displayed unpinned order should follow the stored unpinned list")
    }

    private static func testKeyboardMoveCrossesThePinBoundary() {
        var pinned: [String] = ["a"]
        var unpinned: [String] = ["b"]
        HyperlitePullRequestPinning.move(
            "a", by: 1, pinned: &pinned, unpinned: &unpinned
        )
        expect(pinned.isEmpty && unpinned == ["a", "b"],
               "moving down from the last pinned row should unpin it")
        HyperlitePullRequestPinning.move(
            "a", by: -1, pinned: &pinned, unpinned: &unpinned
        )
        expect(pinned == ["a"] && unpinned == ["b"],
               "moving up from the first unpinned row should pin it")
    }

    private static func testUnpinnedRowsGroupByRepository() {
        let sections = HyperlitePullRequestPinning.sections(
            rows: mixedRows(),
            pinnedIDs: ["p"],
            unpinnedIDs: ["a1", "b1", "a2"]
        )
        expect(sections.pinned.map(\.repository) == ["owner/pin"],
               "pinned rows should stay a mixed list")
        expect(sections.unpinnedGroups.map(\.repository) == ["owner/one", "owner/two"],
               "unpinned groups should follow first-seen repository order")
        expect(sections.unpinnedGroups.map { $0.rows.map(\.id) } == [["a1", "a2"], ["b1"]],
               "rows from the same repository should gather under one section")
    }

    private static func testSameProjectDropReordersInsideTheGroup() {
        var pinned: [String] = []
        var unpinned: [String] = ["a1", "a2", "b1"]
        HyperlitePullRequestPinning.move(
            "a2",
            over: "a1",
            pinned: &pinned,
            unpinned: &unpinned,
            repositories: repositories()
        )
        expect(unpinned == ["a2", "a1", "b1"],
               "dropping inside a project should reorder only that project's rows")
    }

    private static func testCrossProjectDropMovesTheGroup() {
        var pinned: [String] = []
        var unpinned: [String] = ["a1", "a2", "b1"]
        HyperlitePullRequestPinning.move(
            "b1",
            over: "a1",
            pinned: &pinned,
            unpinned: &unpinned,
            repositories: repositories()
        )
        expect(unpinned == ["b1", "a1", "a2"],
               "dropping onto another project should move the whole source group")
        HyperlitePullRequestPinning.move(
            "a2",
            over: "b1",
            pinned: &pinned,
            unpinned: &unpinned,
            repositories: repositories()
        )
        expect(unpinned == ["a1", "a2", "b1"],
               "moving a later row should still move its whole project group")
    }

    private static func testAdjacentDownwardGroupDropMovesTheGroup() {
        var pinned: [String] = []
        var unpinned: [String] = ["a1", "a2", "b1"]
        HyperlitePullRequestPinning.move(
            "a1",
            over: "b1",
            pinned: &pinned,
            unpinned: &unpinned,
            repositories: repositories()
        )
        expect(unpinned == ["b1", "a1", "a2"],
               "dropping a project onto the next project should move that group down")
        unpinned = ["a1", "b1", "c1"]
        HyperlitePullRequestPinning.move(
            "a1",
            over: "c1",
            pinned: &pinned,
            unpinned: &unpinned,
            repositories: repositories()
        )
        expect(unpinned == ["b1", "a1", "c1"],
               "dropping onto a later project should insert immediately before it")
    }

    private static func testKeyboardMoveAtGroupBoundaryMovesTheGroup() {
        var pinned: [String] = []
        var unpinned: [String] = ["a1", "a2", "b1"]
        HyperlitePullRequestPinning.move(
            "a2",
            by: 1,
            pinned: &pinned,
            unpinned: &unpinned,
            repositories: repositories()
        )
        expect(unpinned == ["b1", "a1", "a2"],
               "moving down from the last row in a project should move that group")
        HyperlitePullRequestPinning.move(
            "a1",
            by: -1,
            pinned: &pinned,
            unpinned: &unpinned,
            repositories: repositories()
        )
        expect(unpinned == ["a1", "a2", "b1"],
               "moving up from the first row of a later project should move that group")
        HyperlitePullRequestPinning.move(
            "a1",
            by: -1,
            pinned: &pinned,
            unpinned: &unpinned,
            repositories: repositories()
        )
        expect(pinned == ["a1"] && unpinned == ["a2", "b1"],
               "moving up from the first unpinned row should pin it")
    }

    private static func rows() -> [HyperlitePullRequestRow] {
        ["a", "b", "c"].enumerated().map { index, id in
            row(id: id, repository: "owner/one", number: index + 1)
        }
    }

    private static func mixedRows() -> [HyperlitePullRequestRow] {
        [
            row(id: "p", repository: "owner/pin", number: 9),
            row(id: "a1", repository: "owner/one", number: 1),
            row(id: "b1", repository: "owner/two", number: 2),
            row(id: "a2", repository: "owner/one", number: 3),
        ]
    }

    private static func repositories() -> [String: String] {
        [
            "a1": "owner/one",
            "a2": "owner/one",
            "b1": "owner/two",
            "c1": "owner/three",
        ]
    }

    private static func row(
        id: String,
        repository: String,
        number: Int
    ) -> HyperlitePullRequestRow {
        HyperlitePullRequestRow(
            id: id, reviewID: id, repository: repository, status: .current,
            number: number, title: id, url: nil, headRefOID: "head-\(id)",
            isDraft: false, hasMergeConflict: false, unresolvedReviewThreads: 0,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
