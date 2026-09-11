import Foundation

enum HyperliteOpenPRRefreshPulseTests {
    static func run() {
        testIdleHeaderStaysFullyOpaqueWithoutAGlyph()
        testRefreshingPulseAlternatesAndKeepsTheGhost()
        testAccessibilityNamesTheRefresh()
    }

    private static func testIdleHeaderStaysFullyOpaqueWithoutAGlyph() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        expect(
            HyperliteOpenPRRefreshPulse.titleOpacity(isRefreshing: false, at: date) == 1,
            "idle Open PRs title should stay fully opaque"
        )
        expect(
            !HyperliteOpenPRRefreshPulse.showsGlyph(false),
            "idle Open PRs should not keep a refresh ghost in layout"
        )
    }

    private static func testRefreshingPulseAlternatesAndKeepsTheGhost() {
        let bright = Date(timeIntervalSinceReferenceDate: 0)
        let dim = Date(
            timeIntervalSinceReferenceDate: HyperliteOpenPRRefreshPulse.interval
        )
        expect(
            HyperliteOpenPRRefreshPulse.isBright(at: bright),
            "even interval buckets should be the bright pulse phase"
        )
        expect(
            !HyperliteOpenPRRefreshPulse.isBright(at: dim),
            "odd interval buckets should be the dim pulse phase"
        )
        expect(
            HyperliteOpenPRRefreshPulse.titleOpacity(isRefreshing: true, at: bright) == 1,
            "bright refresh ticks should keep full title opacity"
        )
        expect(
            HyperliteOpenPRRefreshPulse.titleOpacity(isRefreshing: true, at: dim) ==
                HyperliteOpenPRRefreshPulse.dimOpacity,
            "dim refresh ticks should use the quiet opacity"
        )
        expect(
            HyperliteOpenPRRefreshPulse.showsGlyph(true),
            "refresh should keep the ghost in layout so the header does not jump"
        )
        expect(
            HyperliteOpenPRRefreshPulse.interval >= 1,
            "pulse ticks should stay well below display refresh"
        )
    }

    private static func testAccessibilityNamesTheRefresh() {
        expect(
            HyperliteOpenPRRefreshPulse.accessibilityRefreshing ==
                "Refreshing open pull requests from GitHub",
            "VoiceOver should name the in-flight GitHub refresh"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
