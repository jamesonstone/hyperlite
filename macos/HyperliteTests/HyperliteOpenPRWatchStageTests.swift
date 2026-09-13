import Foundation

enum HyperliteOpenPRWatchStageTests {
    static func run() {
        testCompactRowsUseTwoLineStack()
        testStageKindAndDragChrome()
        testHiddenProjectListPresentation()
    }

    private static func testCompactRowsUseTwoLineStack() {
        expect(
            HyperlitePullRequestRowLayout.usesCompactStack(
                compact: true, showRepository: true
            ),
            "pinned mixed Vertical Mode rows should keep the two-line stack"
        )
        expect(
            HyperlitePullRequestRowLayout.usesCompactStack(
                compact: true, showRepository: false
            ),
            "unpinned Vertical Mode rows should use the two-line stack so titles get a line"
        )
        expect(
            !HyperlitePullRequestRowLayout.usesCompactStack(
                compact: false, showRepository: false
            ),
            "stacked project-section rows should stay one line"
        )
        let layout = HyperlitePullRequestPanelRow.layout
        expect(
            layout.metadataLayoutPriority > layout.titleLayoutPriority,
            "ready/draft and number should keep intrinsic width before the title truncates"
        )
        expect(
            !HyperlitePullRequestRowLayout.reservesAlignedConflictColumn(
                compact: true, showRepository: false
            ),
            "two-line compact stacks should not insert a conflict spacer"
        )
        expect(
            HyperlitePullRequestRowLayout.reservesAlignedConflictColumn(
                compact: false, showRepository: false
            ),
            "one-line stacked rows should still reserve conflict width"
        )
    }

    private static func testStageKindAndDragChrome() {
        expect(
            HyperlitePullRequestPanelRow.dragHandleRestOpacity == 0.18,
            "drag handles should recede at rest"
        )
        expect(
            HyperlitePullRequestPanelRow.pinRestOpacity == 0.2,
            "unpinned pins should recede at rest"
        )
        expect(
            HyperliteOpenPRProjectStageKind.notable.lanternIsLive &&
                !HyperliteOpenPRProjectStageKind.notable.lanternUsesAttentionColor &&
                !HyperliteOpenPRProjectStageKind.active.lanternIsLive,
            "running stages keep a live cyan lantern"
        )
        expect(
            HyperliteOpenPRProjectStageKind.alert.lanternIsLive &&
                HyperliteOpenPRProjectStageKind.alert.lanternUsesAttentionColor,
            "failed main/deploy pipelines light an orange lantern"
        )
        expect(
            HyperliteOpenPRProjectStageKind.notable.lanternOpacity >
                HyperliteOpenPRProjectStageKind.idle.lanternOpacity,
            "quiet idle lanterns should recede behind live work"
        )
    }

    private static func testHiddenProjectListPresentation() {
        expect(
            HyperliteHiddenProjectListPresentation.caption == "watching the quiet ones",
            "the collapsible idle list keeps the quiet-ones caption"
        )
        expect(
            HyperliteHiddenProjectListPresentation
                .accessibilityLabel(count: 18) == "watching the quiet ones, 18 idle projects",
            "the collapsible idle list announces its hidden project count"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
