import Foundation

enum HyperliteOpenPRWatchStageTests {
    static func run() {
        testRowLayoutAndStageKind()
        testHiddenProjectListPresentation()
    }

    private static func testRowLayoutAndStageKind() {
        let layout = HyperlitePullRequestPanelRow.layout
        expect(
            layout.metadataLayoutPriority > layout.titleLayoutPriority,
            "ready/draft and number should keep intrinsic width before the title truncates"
        )
        expect(
            HyperlitePullRequestRowLayout.rowChromeLeading == 24,
            "section labels should indent past only the review toggle"
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
        expect(
            HyperliteHiddenProjectListPresentation
                .accessibilityLabel(count: 3, attentionCount: 2)
                == "watching the quiet ones, 3 idle projects, 2 need attention",
            "the collapsible idle list announces how many hidden projects need attention"
        )
        expect(
            HyperliteHiddenProjectListPresentation
                .accessibilityLabel(count: 1, attentionCount: 1)
                == "watching the quiet ones, 1 idle project, 1 needs attention",
            "the quiet-ones announcement stays grammatical for a single project"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
