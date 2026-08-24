import Foundation

struct HyperliteAgentTaskGroup: Equatable, Identifiable {
    let profile: String
    let displayName: String
    let sessions: [HyperliteAgentSession]

    var id: String { profile }
}

enum HyperliteAgentTaskPresentation {
    static func groups(
        sessions: [HyperliteAgentSession],
        integrations: [HyperliteAgentIntegration]
    ) -> [HyperliteAgentTaskGroup] {
        var names: [String: String] = [:]
        for integration in integrations where names[integration.id] == nil {
            names[integration.id] = integration.name
        }

        var grouped: [String: [HyperliteAgentSession]] = [:]
        var profileOrder: [String] = []
        for session in sessions where isVisible(session) {
            if grouped[session.profile] == nil {
                grouped[session.profile] = []
                profileOrder.append(session.profile)
            }
            grouped[session.profile]?.append(session)
        }

        return profileOrder.compactMap { profile in
            guard let profileSessions = grouped[profile] else { return nil }
            return HyperliteAgentTaskGroup(
                profile: profile,
                displayName: names[profile] ?? fallbackName(profile),
                sessions: profileSessions
            )
        }.sorted { left, right in
            let leftPriority = priority(left.sessions)
            let rightPriority = priority(right.sessions)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            let nameOrder = left.displayName.localizedCaseInsensitiveCompare(right.displayName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return left.profile < right.profile
        }
    }

    static func isVisible(_ session: HyperliteAgentSession) -> Bool {
        guard !session.synthetic else { return false }
        switch session.phase {
        case .starting, .processing, .waitingForApproval, .waitingForInput, .idle:
            return true
        case .completed, .error, .ended:
            return false
        }
    }

    private static func priority(_ sessions: [HyperliteAgentSession]) -> Int {
        if sessions.contains(where: \.needsAttention) { return 0 }
        if sessions.contains(where: { $0.phase.isActive }) { return 1 }
        return 2
    }

    private static func fallbackName(_ profile: String) -> String {
        guard !profile.isEmpty else { return "Unknown Client" }
        let acronyms = ["ai": "AI", "cli": "CLI", "cn": "CN"]
        return profile.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { part in
            acronyms[String(part).lowercased()] ?? part.capitalized
        }.joined(separator: " ")
    }
}
