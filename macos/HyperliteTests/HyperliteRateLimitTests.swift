import Foundation

enum HyperliteRateLimitTests {
    static func run() {
        testUnknownAndInvalidStates()
        testCompleteMetadataPresentation()
        testWarningThresholds()
        testBurnRatePresentation()
        testPopoverInteraction()
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
        expect(
            unknown.statusText == "Unavailable" && unknown.usageFraction == nil &&
                unknown.remainingDetailText == "—" &&
                unknown.burnRateText == "Measuring" &&
                unknown.burnLevel == .measuring,
            "missing quota should provide an explicit empty popover state"
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
            "healthy quota should render used out of limit without decoration noise"
        )
        expect(
            presentation.statusText == "Healthy capacity" &&
                presentation.usedDetailText == "1,551" &&
                presentation.limitDetailText == "5,000" &&
                presentation.remainingDetailText == "3,449" &&
                presentation.resetText == "2026-08-02 13:00 GMT" &&
                presentation.costText == "4" && presentation.nodeCountText == "12" &&
                presentation.observedText == "2026-08-02 12:00 GMT" &&
                presentation.usageFraction == 1_551.0 / 5_000.0 &&
                presentation.burnRateText == "Measuring" &&
                presentation.projectedExhaustionText == "—",
            "popover metadata should expose every formatted GitHub quota field"
        )
        expect(
            presentation.accessibilityLabel.contains("healthy capacity") &&
                presentation.accessibilityLabel.contains("3,449 remaining") &&
                presentation.accessibilityLabel.contains("node count 12"),
            "accessibility should expose quota and last-query metadata"
        )
    }

    private static func testBurnRatePresentation() {
        let beforeReset = HyperliteRateLimitPresentation.make(
            rateLimit: fixture(
                used: 1_551,
                remaining: 3_449,
                burnRate: HyperliteGitHubRateLimitBurnRate(
                    pointsPerHour: 4_000,
                    sampleSeconds: 300,
                    projectedExhaustionAt: Date(timeIntervalSince1970: 1_785_675_104.1)
                )
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        expect(
            beforeReset.burnRateText == "4,000 pts/hr" &&
                beforeReset.burnSampleText == "5 min sample" &&
                beforeReset.projectedExhaustionText == "2026-08-02 12:51 GMT" &&
                beforeReset.burnComparisonText == "Before reset" &&
                beforeReset.burnLevel == .risk,
            "a depletion forecast before reset should be explicit and attention colored"
        )
        expect(
            beforeReset.accessibilityLabel.contains("burn rate 4,000 pts/hr") &&
                beforeReset.accessibilityLabel.contains("before reset"),
            "accessibility should include the burn-rate forecast and comparison"
        )

        let afterReset = HyperliteRateLimitPresentation.make(
            rateLimit: fixture(
                used: 1_551,
                remaining: 3_449,
                burnRate: HyperliteGitHubRateLimitBurnRate(
                    pointsPerHour: 1_000,
                    sampleSeconds: 3_600,
                    projectedExhaustionAt: Date(timeIntervalSince1970: 1_785_684_416.4)
                )
            ),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        expect(
            afterReset.burnSampleText == "1 hr sample" &&
                afterReset.projectedExhaustionText == "2026-08-02 15:26 GMT" &&
                afterReset.burnComparisonText == "After reset" &&
                afterReset.burnLevel == .sustainable,
            "a depletion forecast after reset should remain visibly sustainable"
        )

        let zero = HyperliteRateLimitPresentation.make(
            rateLimit: fixture(
                used: 1_551,
                remaining: 3_449,
                burnRate: HyperliteGitHubRateLimitBurnRate(
                    pointsPerHour: 0,
                    sampleSeconds: 300,
                    projectedExhaustionAt: nil
                )
            )
        )
        expect(
            zero.burnRateText == "0 pts/hr" &&
                zero.projectedExhaustionText == "No depletion projected" &&
                zero.burnComparisonText == "Through reset" &&
                zero.burnLevel == .sustainable,
            "zero consumption should not invent an exhaustion timestamp"
        )

        let malformed = HyperliteRateLimitPresentation.make(
            rateLimit: fixture(
                used: 1_551,
                remaining: 3_449,
                burnRate: HyperliteGitHubRateLimitBurnRate(
                    pointsPerHour: 1_000,
                    sampleSeconds: 300,
                    projectedExhaustionAt: Date(timeIntervalSince1970: 1_785_672_060)
                )
            )
        )
        expect(
            malformed.burnRateText == "Measuring" &&
                malformed.burnComparisonText == "Awaiting trend" &&
                malformed.burnLevel == .measuring,
            "invalid derived metadata should not hide otherwise valid quota data"
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

    private static func testPopoverInteraction() {
        var interaction = HyperliteRateLimitPopoverInteraction()
        interaction.setTriggerHovered(true)
        interaction.openFromHoverIfNeeded()
        expect(
            interaction.isPresented && !interaction.isPinned,
            "hover should open a transient popover"
        )

        interaction.setTriggerHovered(false)
        interaction.setPopoverHovered(true)
        interaction.closeIfIdle()
        expect(interaction.isPresented, "moving into the popover should keep it open")
        interaction.setPopoverHovered(false)
        interaction.closeIfIdle()
        expect(!interaction.isPresented, "leaving an unpinned popover should close it")

        interaction.togglePinned()
        expect(
            interaction.isPresented && interaction.isPinned,
            "click should open and pin the popover immediately"
        )
        interaction.closeIfIdle()
        expect(interaction.isPresented, "idle close should not dismiss a pinned popover")
        interaction.togglePinned()
        expect(
            !interaction.isPresented && !interaction.isPinned,
            "a second click should dismiss and unpin the popover"
        )

        interaction.togglePinned()
        interaction.dismiss()
        expect(
            !interaction.isPresented && !interaction.isPinned,
            "native dismissal should clear pinned interaction state"
        )
    }

    private static func fixture(
        used: Int,
        remaining: Int,
        cost: Int = 1,
        nodes: Int = 0,
        burnRate: HyperliteGitHubRateLimitBurnRate? = nil
    ) -> HyperliteGitHubRateLimit {
        HyperliteGitHubRateLimit(
            limit: 5_000,
            used: used,
            remaining: remaining,
            resetAt: Date(timeIntervalSince1970: 1_785_675_600),
            cost: cost,
            nodeCount: nodes,
            observedAt: Date(timeIntervalSince1970: 1_785_672_000),
            burnRate: burnRate
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
