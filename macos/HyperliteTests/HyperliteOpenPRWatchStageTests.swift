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
        let star = HyperliteProjectCelestialKind.star.emoji(for: "a")
        expect(
            hasEmoji(star, 0x2B50) || hasEmoji(star, 0x1F31F),
            "stars should render as star emoji; got \(star.unicodeScalars.map(\.value))"
        )
        let moon = HyperliteProjectCelestialKind.moon.emoji(for: "a")
        expect(
            hasEmoji(moon, 0x1F315) || hasEmoji(moon, 0x1F316) || hasEmoji(moon, 0x1F317),
            "moons should render as moon emoji; got \(moon.unicodeScalars.map(\.value))"
        )
        expect(
            hasEmoji(HyperliteProjectOrbitPresentation.sunEmoji, 0x2600),
            "the orbit should keep a sun as the reference"
        )
        expect(
            HyperliteProjectOrbitPresentation.revolutionPeriod >= 60,
            "revolution should stay a slow Core Animation, not a 12 Hz tick"
        )
        let size = CGSize(width: 240, height: 180)
        let inset = HyperliteProjectOrbitPresentation.inset
        let hit = HyperliteProjectOrbitPresentation.bodyHitSize
        let usableHeight = size.height - HyperliteProjectOrbitPresentation.captionReserve
        expect(
            HyperliteProjectOrbitPresentation.radius(in: size) * 2
                + HyperliteProjectOrbitPresentation.bodyClearance * 2
                <= min(size.width, usableHeight) + 0.5,
            "orbit diameter should scale to leftover, not overflow it"
        )
        var homes: [CGPoint] = []
        for index in 0..<17 {
            let point = HyperliteProjectOrbitPresentation.bodyPoint(
                index: index, count: 17, in: size
            )
            expect(
                point.x >= inset && point.x <= size.width - inset &&
                    point.y >= inset && point.y <= size.height - inset,
                "body \(index) should stay inside the leftover sky; got \(point)"
            )
            expect(
                point.x - hit.width / 2 >= -0.5 &&
                    point.x + hit.width / 2 <= size.width + 0.5 &&
                    point.y - hit.height / 2 >= -0.5 &&
                    point.y + hit.height / 2 <= size.height + 0.5,
                "body \(index) hit frame should stay in leftover; got \(point)"
            )
            homes.append(point)
        }
        expect(
            Set(homes.map { "\($0.x)-\($0.y)" }).count == 17,
            "every hidden project should rest on its own orbit slot"
        )
        let origin = homes[0]
        let clamped = HyperliteProjectOrbitPresentation.clampOffset(
            CGSize(width: 800, height: -900), origin: origin, in: size
        )
        let pulled = CGPoint(x: origin.x + clamped.width, y: origin.y + clamped.height)
        expect(
            pulled.x - hit.width / 2 >= -0.5 &&
                pulled.x + hit.width / 2 <= size.width + 0.5 &&
                pulled.y - hit.height / 2 >= -0.5 &&
                pulled.y + hit.height / 2 <= size.height + 0.5,
            "drag should stay inside leftover; got \(pulled)"
        )
        expect(
            HyperliteProjectOrbitPresentation.returnSpringIsUnderdamped,
            "released bodies should bounce once before settling"
        )
        expect(
            HyperliteProjectOrbitPresentation.dragSlop >= 3,
            "clicks should not start a pull"
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

    private static func hasEmoji(_ value: String, _ scalar: UInt32) -> Bool {
        value.unicodeScalars.contains { $0.value == scalar }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
