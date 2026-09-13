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
        let bob = HyperliteHiddenProjectGhostSkyPresentation.floatOffset(for: "/repo/two")
        expect(bob >= -4 && bob <= 4, "ghost float should stay a small static offset; got \(bob)")
        let tilt = HyperliteHiddenProjectGhostSkyPresentation.tiltDegrees(for: "/repo/two")
        expect(tilt >= -4 && tilt <= 4, "ghost tilt should stay a small static angle; got \(tilt)")
        expect(
            HyperliteHiddenProjectGhostSkyPresentation.opacity(for: "/a") !=
                HyperliteHiddenProjectGhostSkyPresentation.opacity(for: "/b") ||
                HyperliteHiddenProjectGhostSkyPresentation.floatOffset(for: "/a") !=
                HyperliteHiddenProjectGhostSkyPresentation.floatOffset(for: "/b"),
            "different projects should not all share the same ghost pose"
        )
    }

    private static func testStageKindAndDragChrome() {
        expect(
            HyperlitePullRequestPanelRow.dragHandleRestOpacity == 0.32,
            "drag handles should recede at rest"
        )
        expect(
            HyperliteOpenPRProjectStageKind.pinned.fillOpacity >
                HyperliteOpenPRProjectStageKind.idle.fillOpacity,
            "idle stages should recede behind projects with work"
        )
        expect(
            HyperliteOpenPRProjectStageKind.notable.showsLiveStroke &&
                !HyperliteOpenPRProjectStageKind.active.showsLiveStroke,
            "only running or failing stages get a live cyan stroke"
        )
        expect(
            !HyperliteOpenPRProjectStageKind.idle.showsLiveStroke,
            "quiet idle stages should not glow"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
