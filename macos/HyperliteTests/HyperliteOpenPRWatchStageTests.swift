import Foundation

enum HyperliteOpenPRWatchStageTests {
    static func run() {
        testCompactRowsUseTwoLineStack()
        testGhostSkyMembership()
        testOrbitPresentation()
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

    private static func testOrbitPresentation() {
        expect(
            HyperliteHiddenProjectGhostSkyPresentation.shortName("lsmc-bio/labcore") == "labcore",
            "orbit labels should use the short repository name"
        )
        expect(
            HyperliteProjectOrbitPresentation.classify(count: nil) == .star &&
                HyperliteProjectOrbitPresentation.classify(count: 40) == .star &&
                HyperliteProjectOrbitPresentation.classify(count: 400) == .moon &&
                HyperliteProjectOrbitPresentation.classify(count: 4200) == .planet &&
                HyperliteProjectOrbitPresentation.classify(count: 48000) == .giant,
            "commit count should pick star, moon, planet, or giant"
        )
        expect(
            HyperliteProjectOrbitPresentation.cometCount == 3,
            "decorative ghosts should stay a handful of comets"
        )
        let size = CGSize(width: 240, height: 180)
        let inset = HyperliteProjectOrbitPresentation.inset
        for index in 0..<17 {
            let point = HyperliteProjectOrbitPresentation.bodyPoint(
                index: index, count: 17, in: size, phase: 0.4
            )
            expect(
                point.x >= inset && point.x <= size.width - inset &&
                    point.y >= inset && point.y <= size.height - inset,
                "body \(index) should stay inside the leftover sky; got \(point)"
            )
        }
        let first = HyperliteProjectOrbitPresentation.bodyPoint(
            index: 0, count: 17, in: size, phase: 0
        )
        let shifted = HyperliteProjectOrbitPresentation.bodyPoint(
            index: 0, count: 17, in: size, phase: .pi
        )
        expect(first != shifted, "orbit phase should move bodies around the sun")
        expect(
            HyperliteProjectOrbitPresentation.phase(at: Date(), reduceMotion: true) == 0,
            "Reduce Motion should freeze the orbit"
        )
        let kinds = HyperliteProjectOrbitPresentation.kinds(for: [
            project(path: "/small", count: 12),
            project(path: "/huge", count: 50000),
        ])
        expect(
            kinds["/small"] == .star && kinds["/huge"] == .giant,
            "every project should get a celestial kind"
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

    private static func project(path: String, count: Int) -> HyperliteProjectPullRequests {
        HyperliteProjectPullRequests(
            id: path, name: path, path: path, repository: "owner\(path)",
            status: .current, message: nil, checkedAt: nil, observedAt: nil,
            pullRequests: [], commitCount: count
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
