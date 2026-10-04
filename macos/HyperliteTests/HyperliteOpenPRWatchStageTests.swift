import Foundation

enum HyperliteOpenPRWatchStageTests {
    static func run() {
        testRowLayoutAndStageKind()
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
