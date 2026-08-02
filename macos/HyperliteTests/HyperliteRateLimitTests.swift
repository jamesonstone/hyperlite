import Foundation

enum HyperliteRateLimitTests {
    static func run() {
        testUnknownAndInvalidStates()
        testCompleteMetadataPresentation()
        testWarningThresholds()
    }

    private static func testUnknownAndInvalidStates() {
        let unknown = HyperliteRateLimitPresentation.make(rateLimit: nil)
        expect(
            unknown.usedText == "?" && unknown.limitText == "?" &&
                unknown.level == .unknown,
            "missing quota should render an explicit unknown fraction"
        )
        expect(
            unknown.accessibilityLabel == "GitHub GraphQL rate limit unavailable",
            "missing quota should remain explicit to accessibility"
        )

        let invalid = fixture(used: 100, remaining: 4_899)
        expect(
            HyperliteRateLimitPresentation.make(rateLimit: invalid).level == .unknown,
            "an inconsistent quota should not be presented as current"
        )
    }

    private static func testCompleteMetadataPresentation() {
        let presentation = HyperliteRateLimitPresentation.make(
            rateLimit: fixture(used: 1_551, remaining: 3_449, cost: 4, nodes: 12),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        expect(
            presentation.usedText == "1551" && presentation.limitText == "5000" &&
                presentation.level == .healthy,
            "healthy quota should render used over limit without decoration noise"
        )
        for metadata in [
            "GitHub GraphQL rate limit",
            "Status: Healthy capacity",
            "Used: 1,551 of 5,000",
            "Remaining: 3,449",
            "Resets: 2026-08-02 13:00 GMT",
            "Last query cost: 4",
            "Last query nodes: 12",
            "Observed: 2026-08-02 12:00 GMT",
        ] {
            expect(
                presentation.helpText.contains(metadata),
                "hover metadata should include \(metadata)"
            )
        }
        expect(
            presentation.accessibilityLabel.contains("healthy capacity") &&
                presentation.accessibilityLabel.contains("3,449 remaining") &&
                presentation.accessibilityLabel.contains("node count 12"),
            "accessibility should expose quota and last-query metadata"
        )
    }

    private static func testWarningThresholds() {
        expect(
            HyperliteRateLimitPresentation.make(
                rateLimit: fixture(used: 3_999, remaining: 1_001)
            ).level == .healthy,
            "capacity above twenty percent should stay quiet"
        )
        let warning = HyperliteRateLimitPresentation.make(
            rateLimit: fixture(used: 4_000, remaining: 1_000)
        )
        expect(
            warning.level == .warning &&
                warning.accessibilityLabel.contains("low capacity warning"),
            "twenty percent remaining should warn"
        )
        let critical = HyperliteRateLimitPresentation.make(
            rateLimit: fixture(used: 4_500, remaining: 500)
        )
        expect(
            critical.level == .critical &&
                critical.accessibilityLabel.contains("critical capacity"),
            "ten percent remaining should be critical"
        )
    }

    private static func fixture(
        used: Int,
        remaining: Int,
        cost: Int = 1,
        nodes: Int = 0
    ) -> HyperliteGitHubRateLimit {
        HyperliteGitHubRateLimit(
            limit: 5_000,
            used: used,
            remaining: remaining,
            resetAt: Date(timeIntervalSince1970: 1_785_675_600),
            cost: cost,
            nodeCount: nodes,
            observedAt: Date(timeIntervalSince1970: 1_785_672_000)
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
