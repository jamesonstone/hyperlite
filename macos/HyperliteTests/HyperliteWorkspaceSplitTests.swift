import Foundation
import AppKit

enum HyperliteWorkspaceSplitTests {
    static func run() {
        testStackedFitUsesContentAndCap()
        testVerticalDefaultIsNarrowerThanHalf()
        testFractionClampingAndDelta()
        testNotepadMeasureAndSummary()
        testTitleFirstAndCompactRows()
        testEstimatedStackedHeightUsesCounts()
    }

    private static func testStackedFitUsesContentAndCap() {
        let container: CGFloat = 1000
        let short = HyperliteWorkspaceSplit.stackedPullRequestHeight(
            fraction: HyperliteWorkspaceSplit.fitContent,
            contentHeight: 180,
            containerHeight: container
        )
        expect(abs(short - 180) < 0.5,
               "short Open PRs should keep their content height in stacked mode")
        let tall = HyperliteWorkspaceSplit.stackedPullRequestHeight(
            fraction: HyperliteWorkspaceSplit.fitContent,
            contentHeight: 800,
            containerHeight: container
        )
        expect(abs(tall - container * HyperliteWorkspaceSplit.stackedFitCap) < 0.5,
               "tall Open PRs should cap at 48 percent so notes keep leftover space")
        let dragged = HyperliteWorkspaceSplit.stackedPullRequestHeight(
            fraction: 0.6,
            contentHeight: 180,
            containerHeight: container
        )
        expect(abs(dragged - 600) < 0.5,
               "a dragged stacked split should honor the persisted fraction")
    }

    private static func testVerticalDefaultIsNarrowerThanHalf() {
        let width = HyperliteWorkspaceSplit.verticalPullRequestWidth(
            fraction: HyperliteWorkspaceSplit.fitContent,
            containerWidth: 1000
        )
        expect(abs(width - 360) < 0.5,
               "Vertical Mode should default Open PRs to 36 percent width")
        expect(HyperliteWorkspaceSplit.defaultVerticalFraction < 0.5,
               "the default vertical split must stay narrower than half")
        let custom = HyperliteWorkspaceSplit.verticalPullRequestWidth(
            fraction: 0.25,
            containerWidth: 800
        )
        expect(abs(custom - 200) < 0.5,
               "a persisted vertical fraction should size the Open PRs pane")
    }

    private static func testFractionClampingAndDelta() {
        expect(HyperliteWorkspaceSplit.clamped(0.05) == HyperliteWorkspaceSplit.minFraction,
               "tiny splits should clamp to the minimum pane size")
        expect(HyperliteWorkspaceSplit.clamped(0.95) == HyperliteWorkspaceSplit.maxFraction,
               "huge splits should clamp to the maximum pane size")
        expect(
            abs(HyperliteWorkspaceSplit.fractionDelta(translation: 100, container: 500) - 0.2)
                < 0.0001,
            "drag translation should convert to a fraction of the container"
        )
        expect(
            HyperliteWorkspaceSplit.fractionDelta(translation: 10, container: 0) == 0,
            "a zero container should not produce an infinite split delta"
        )
        let displayed = HyperliteWorkspaceSplit.displayedStackedFraction(
            fraction: HyperliteWorkspaceSplit.fitContent,
            contentHeight: 200,
            containerHeight: 800
        )
        expect(abs(displayed - 0.25) < 0.0001,
               "fit-content drag origin should start from the rendered Open PRs height")
    }

    private static func testNotepadMeasureAndSummary() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let width = HyperliteWorkspaceSplit.notepadMeasureWidth(font: font)
        let expected = font.maximumAdvancement.width * 80 + 16
        expect(abs(width - expected) < 0.5,
               "notepad measure should be 80 columns of the editor font")
        expect(
            HyperliteWorkspaceSplit.summaryTitle(openCount: 4, pinnedCount: 0) ==
                "Open PRs 4 · Pinned 0",
            "Notes Only should summarize open and pinned counts"
        )
    }

    private static func testTitleFirstAndCompactRows() {
        let layout = HyperlitePullRequestPanelRow.layout
        expect(layout == HyperlitePullRequestRowLayout.titleFirst,
               "Open PR rows should use the title-first layout")
        expect(
            layout.titleLayoutPriority > layout.repositoryLayoutPriority,
            "Open PR title should keep space before repository identity"
        )
        expect(
            layout.repositoryColumnWidth <= 160,
            "title-first repository column should leave room for the title"
        )
        expect(
            HyperliteWorkspaceSplit.compactRows(verticalMode: true, notesOnly: false),
            "Vertical Mode should use two-line Open PR rows"
        )
        expect(
            !HyperliteWorkspaceSplit.compactRows(verticalMode: false, notesOnly: false),
            "stacked Open PR rows should stay one line"
        )
        expect(
            !HyperliteWorkspaceSplit.compactRows(verticalMode: true, notesOnly: true),
            "Notes Only should not keep compact rows in memory"
        )
    }

    private static func testEstimatedStackedHeightUsesCounts() {
        let short = HyperliteWorkspaceSplit.estimatedStackedContentHeight(
            pinnedCount: 0,
            openCount: 4,
            availabilityCount: 0,
            compactRows: false,
            hasStatusMessage: false
        )
        expect(short > HyperliteWorkspaceSplit.minimumStackedPullRequestHeight,
               "a short Open PRs list should still keep a usable pane")
        expect(short < 250,
               "four stacked rows should stay content-sized instead of half the window")
        let empty = HyperliteWorkspaceSplit.estimatedStackedContentHeight(
            pinnedCount: 0,
            openCount: 0,
            availabilityCount: 0,
            compactRows: false,
            hasStatusMessage: false
        )
        expect(empty == HyperliteWorkspaceSplit.minimumStackedPullRequestHeight,
               "an empty Open PRs list should use the minimum stacked pane height")
        let fitted = HyperliteWorkspaceSplit.stackedPullRequestHeight(
            fraction: HyperliteWorkspaceSplit.fitContent,
            contentHeight: short,
            containerHeight: 1000
        )
        expect(abs(fitted - short) < 0.5,
               "fit-content stacked height should use the row-count estimate")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
