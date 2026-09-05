import Foundation

enum HyperliteAgentLaunchDestination: Equatable {
    case dashboard
    case onboarding
}

enum HyperliteAgentLaunchPolicy {
    static func tracksSessions(featureEnabled: Bool, hasConsent: Bool) -> Bool {
        featureEnabled && hasConsent
    }

    static func destination(
        featureEnabled: Bool,
        hasConsent: Bool
    ) -> HyperliteAgentLaunchDestination {
        guard featureEnabled else { return .dashboard }
        guard hasConsent else { return .onboarding }
        return .dashboard
    }
}
