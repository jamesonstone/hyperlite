import Combine
import Foundation

@MainActor
final class HyperliteAgentIslandPreference: ObservableObject {
    static let shared = HyperliteAgentIslandPreference()
    static let key = "hyperlite.agent-island-enabled"

    @Published private(set) var isEnabled: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.key) == nil
            ? true
            : defaults.bool(forKey: Self.key)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        defaults.set(enabled, forKey: Self.key)
        isEnabled = enabled
    }

    func toggle() {
        setEnabled(!isEnabled)
    }
}

enum HyperliteAgentIslandLaunchDestination: Equatable {
    case island
    case dashboard
    case onboarding
}

enum HyperliteAgentIslandLaunchPolicy {
    static func tracksSessions(featureEnabled: Bool, hasConsent: Bool) -> Bool {
        featureEnabled && hasConsent
    }

    static func destination(
        featureEnabled: Bool,
        hasConsent: Bool,
        islandEnabled: Bool
    ) -> HyperliteAgentIslandLaunchDestination {
        guard featureEnabled else { return .dashboard }
        guard hasConsent else { return .onboarding }
        return islandEnabled ? .island : .dashboard
    }

    static func showsPanel(
        featureEnabled: Bool,
        hasConsent: Bool,
        islandEnabled: Bool
    ) -> Bool {
        tracksSessions(featureEnabled: featureEnabled, hasConsent: hasConsent) && islandEnabled
    }
}
