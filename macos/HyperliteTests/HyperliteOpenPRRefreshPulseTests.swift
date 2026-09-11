import Foundation

enum HyperliteOpenPRRefreshPulseTests {
    static func run() {
        testIdleGhostRestsAtZeroWithoutAnOverlay()
        testRefreshingSpinCompletesATurnThenPausesAtZero()
        testAccessibilityNamesTheRefresh()
    }

    private static func testIdleGhostRestsAtZeroWithoutAnOverlay() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        expect(
            HyperliteOpenPRRefreshPulse.rotationDegrees(isRefreshing: false, at: date) == 0,
            "idle Open PRs overlay should rest at 0 degrees"
        )
        expect(
            !HyperliteOpenPRRefreshPulse.showsOverlay(false),
            "idle Open PRs should not keep a refresh overlay in the tree"
        )
    }

    private static func testRefreshingSpinCompletesATurnThenPausesAtZero() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let halfway = Date(
            timeIntervalSinceReferenceDate: HyperliteOpenPRRefreshPulse.spinDuration / 2
        )
        let pause = Date(
            timeIntervalSinceReferenceDate: HyperliteOpenPRRefreshPulse.spinDuration
        )
        let stillPaused = Date(
            timeIntervalSinceReferenceDate: HyperliteOpenPRRefreshPulse.spinDuration
                + HyperliteOpenPRRefreshPulse.pauseDuration / 2
        )
        expect(
            HyperliteOpenPRRefreshPulse.rotationDegrees(isRefreshing: true, at: start) == 0,
            "a new spin should start at 0 degrees"
        )
        let halfwayDegrees = HyperliteOpenPRRefreshPulse.rotationDegrees(
            isRefreshing: true, at: halfway
        )
        expect(
            abs(halfwayDegrees - 180) < 0.01,
            "mid-spin should face the opposite way"
        )
        expect(
            HyperliteOpenPRRefreshPulse.rotationDegrees(isRefreshing: true, at: pause) == 0,
            "completed turns should pause at 0 degrees"
        )
        expect(
            HyperliteOpenPRRefreshPulse.rotationDegrees(isRefreshing: true, at: stillPaused) == 0,
            "the rest pause should hold at 0 degrees"
        )
        expect(
            HyperliteOpenPRRefreshPulse.showsOverlay(true),
            "refresh should keep the overlay in the pane"
        )
        expect(
            HyperliteOpenPRRefreshPulse.tickInterval >= 1.0 / 15.0,
            "overlay ticks should stay well below display refresh"
        )
        expect(
            HyperliteOpenPRRefreshPulse.pauseDuration > 0,
            "each turn should pause at rest before spinning again"
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
