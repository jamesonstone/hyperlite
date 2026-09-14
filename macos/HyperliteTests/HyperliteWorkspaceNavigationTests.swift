import Foundation

enum HyperliteWorkspaceNavigationTests {
    static func run() {
        testCommandClassification()
        testSelectionMovement()
        testReconciledSelection()
        testHeaderID()
    }

    private static func testCommandClassification() {
        expect(
            HyperliteWorkspaceNavigation.command(keyCode: 125, characters: "") == .next,
            "the down arrow moves to the next item"
        )
        expect(
            HyperliteWorkspaceNavigation.command(keyCode: 126, characters: "") == .previous,
            "the up arrow moves to the previous item"
        )
        expect(
            HyperliteWorkspaceNavigation.command(keyCode: 36, characters: "\r") == .activate,
            "return activates the selection"
        )
        expect(
            HyperliteWorkspaceNavigation.command(keyCode: 76, characters: "") == .activate,
            "keypad enter activates the selection"
        )
        expect(
            HyperliteWorkspaceNavigation.command(keyCode: 38, characters: "j") == .next,
            "j moves to the next item like the command palette"
        )
        expect(
            HyperliteWorkspaceNavigation.command(keyCode: 40, characters: "k") == .previous,
            "k moves to the previous item"
        )
        expect(
            HyperliteWorkspaceNavigation.command(keyCode: 40, characters: "K") == .previous,
            "a shifted K still moves to the previous item"
        )
        expect(
            HyperliteWorkspaceNavigation.command(keyCode: 0, characters: "a") == nil,
            "unrelated keys are not navigation commands"
        )
    }

    private static func testSelectionMovement() {
        let ids = ["a", "b", "c"]
        expect(
            HyperliteWorkspaceNavigation.movedSelectionID(current: nil, ids: ids, by: 1) == "a",
            "the first move from no selection lands on the first item"
        )
        expect(
            HyperliteWorkspaceNavigation.movedSelectionID(current: "a", ids: ids, by: 1) == "b",
            "next advances one item"
        )
        expect(
            HyperliteWorkspaceNavigation.movedSelectionID(current: "c", ids: ids, by: 1) == "c",
            "next clamps at the last item"
        )
        expect(
            HyperliteWorkspaceNavigation.movedSelectionID(current: "a", ids: ids, by: -1) == "a",
            "previous clamps at the first item"
        )
        expect(
            HyperliteWorkspaceNavigation.movedSelectionID(current: "b", ids: [], by: 1) == nil,
            "an empty list has no selection"
        )
        expect(
            HyperliteWorkspaceNavigation.movedSelectionID(current: "gone", ids: ids, by: 1) == "a",
            "a stale selection restarts at the first item"
        )
    }

    private static func testReconciledSelection() {
        let ids = ["x", "y"]
        expect(
            HyperliteWorkspaceNavigation.reconciledSelectionID("y", ids: ids) == "y",
            "a still-present selection is kept"
        )
        expect(
            HyperliteWorkspaceNavigation.reconciledSelectionID("z", ids: ids) == nil,
            "a dropped selection clears rather than jumping to an unrelated item"
        )
        expect(
            HyperliteWorkspaceNavigation.reconciledSelectionID(nil, ids: ids) == nil,
            "no selection stays cleared until the operator navigates"
        )
        expect(
            HyperliteWorkspaceNavigation.reconciledSelectionID("x", ids: []) == nil,
            "an empty list clears the selection"
        )
    }

    private static func testHeaderID() {
        expect(
            HyperliteWorkspaceNavigation.headerID(sectionID: "/repo/one") == "header:/repo/one",
            "header ids namespace the section id so headings and rows never collide"
        )
        expect(
            HyperliteWorkspaceNavigation.quietOnesID == "quiet-ones",
            "the quiet-ones toggle keeps a stable navigation id"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
