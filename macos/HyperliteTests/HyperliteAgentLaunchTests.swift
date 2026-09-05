import Foundation

enum HyperliteAgentLaunchTests {
    static func run() {
        expect(HyperliteAgentLaunchPolicy.destination(
            featureEnabled: false, hasConsent: false
        ) == .dashboard, "disabled preview opens Dashboard")
        expect(HyperliteAgentLaunchPolicy.destination(
            featureEnabled: false, hasConsent: true
        ) == .dashboard, "disabled preview ignores consent and opens Dashboard")
        expect(HyperliteAgentLaunchPolicy.destination(
            featureEnabled: true, hasConsent: false
        ) == .onboarding, "unconsented launch stays on Agent Tasks onboarding")
        expect(HyperliteAgentLaunchPolicy.destination(
            featureEnabled: true, hasConsent: true
        ) == .dashboard, "consented launch opens the regular Dashboard window")
        expect(
            HyperliteAgentLaunchPolicy.tracksSessions(featureEnabled: true, hasConsent: true),
            "tracking remains active without an island"
        )
        expect(
            !HyperliteAgentLaunchPolicy.tracksSessions(featureEnabled: true, hasConsent: false),
            "tracking still waits for consent"
        )
        expect(HyperliteWorkspace.allCases.contains(.sessions), "sessions workspace exists")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
