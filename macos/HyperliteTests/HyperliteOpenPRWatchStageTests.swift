import Foundation

enum HyperliteOpenPRWatchStageTests {
    static func run() {
        testCompactRowsUseTwoLineStack()
        testGhostSkyMembership()
        testGhostTokenPresentation()
        testStageKindAndDragChrome()
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

    private static func testGhostSkyMembership() {
        expect(
            HyperliteHiddenProjectGhostSkyPresentation.showsSky(
                compact: true, hideIdle: true, hiddenCount: 18, leftover: 220
            ),
            "Vertical Mode leftover under hide-idle should show the ghost sky"
        )
        expect(
            !HyperliteHiddenProjectGhostSkyPresentation.showsSky(
                compact: false, hideIdle: true, hiddenCount: 18, leftover: 220
            ),
            "stacked leftover height should stay with notes instead of a sky"
        )
        expect(
            !HyperliteHiddenProjectGhostSkyPresentation.showsSky(
                compact: true, hideIdle: false, hiddenCount: 18, leftover: 220
            ),
            "showing idle projects should not also render them as ghosts"
        )
        expect(
            !HyperliteHiddenProjectGhostSkyPresentation.showsSky(
                compact: true, hideIdle: true, hiddenCount: 0, leftover: 220
            ),
            "an empty hidden set should not render a sky"
        )
        expect(
            !HyperliteHiddenProjectGhostSkyPresentation.showsSky(
                compact: true, hideIdle: true, hiddenCount: 18, leftover: 12
            ),
            "a tiny leftover well should not force a sky"
        )
    }

    private static func testGhostTokenPresentation() {
        expect(
            HyperliteHiddenProjectGhostSkyPresentation.shortName("lsmc-bio/labcore") == "labcore",
            "ghosts should use the short repository name"
        )
        expect(
            HyperliteHiddenProjectGhostSkyPresentation.shortName("terrarium") == "terrarium",
            "a bare repository name should stay intact"
        )
        let opacity = HyperliteHiddenProjectGhostSkyPresentation.opacity(for: "/repo/two")
        expect(
            opacity >= HyperliteHiddenProjectGhostSkyPresentation.minOpacity &&
                opacity <= HyperliteHiddenProjectGhostSkyPresentation.maxOpacity,
            "ghost opacity should stay in the muted watch range; got \(opacity)"
        )
        let bob = HyperliteHiddenProjectGhostSkyPresentation.drift(for: "/repo/two")
        expect(abs(bob.width) <= 4 && abs(bob.height) <= 5,
               "ghost drift should stay a small amplitude; got \(bob)")
        let size = CGSize(width: 240, height: 180)
        for index in 0..<18 {
            let point = HyperliteHiddenProjectGhostSkyPresentation.point(
                for: "/repo/\(index)", index: index, count: 18, in: size
            )
            let inset = HyperliteHiddenProjectGhostSkyPresentation.inset
            expect(
                point.x >= inset && point.x <= size.width - inset &&
                    point.y >= inset && point.y <= size.height - inset,
                "ghost \(index) should stay inside the leftover sky; got \(point)"
            )
        }
        expect(
            HyperliteHiddenProjectGhostSkyPresentation.opacity(for: "/a") !=
                HyperliteHiddenProjectGhostSkyPresentation.opacity(for: "/b") ||
                HyperliteHiddenProjectGhostSkyPresentation.glyphSize(for: "/a") !=
                HyperliteHiddenProjectGhostSkyPresentation.glyphSize(for: "/b"),
            "different projects should not all share the same ghost pose"
        )
        expect(
            HyperliteHiddenProjectGhostSkyPresentation.driftDuration(for: "/repo/two") >= 3,
            "ghost drift should stay slow enough to watch"
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
                !HyperliteOpenPRProjectStageKind.active.lanternIsLive,
            "only running or failing stages get a live cyan lantern"
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
