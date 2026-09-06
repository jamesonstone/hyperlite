import Foundation

enum HyperlitePullRequestPinningTests {
    static func run() {
        testNewRowsStayUnpinnedUntilDragged()
        testDraggingIntoPinnedFlipsStateAndOrder()
        testKeyboardMoveCrossesThePinBoundary()
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

    private static func rows() -> [HyperlitePullRequestRow] {
        ["a", "b", "c"].enumerated().map { index, id in
            HyperlitePullRequestRow(
                id: id, reviewID: id, repository: "owner/one", status: .current,
                number: index + 1, title: id, url: nil, headRefOID: "head-\(id)",
                isDraft: false, hasMergeConflict: false, unresolvedReviewThreads: 0,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
