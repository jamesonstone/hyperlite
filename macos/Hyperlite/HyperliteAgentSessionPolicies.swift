import Foundation

struct HyperliteAgentIntegrationOutcome: Equatable {
    let shouldGrantConsent: Bool
    let shouldRestartService: Bool
}

enum HyperliteAgentIntegrationOutcomePolicy {
    static func resolve(
        wasConsented: Bool,
        grantsConsentOnSuccess: Bool,
        successfulMutations: Int,
        failedMutations _: Int,
        refreshSucceeded _: Bool
    ) -> HyperliteAgentIntegrationOutcome {
        let changed = successfulMutations > 0
        return HyperliteAgentIntegrationOutcome(
            shouldGrantConsent: !wasConsented && grantsConsentOnSuccess && changed,
            shouldRestartService: wasConsented && changed
        )
    }
}

enum HyperliteAgentRoutePolicy {
    static func destination(
        openInClient: Bool,
        routing: HyperliteAgentRouting
    ) -> HyperliteAgentRouteDestination? {
        guard openInClient else { return nil }
        if let bundleID = nonempty(routing.bundleID) {
            return .application(applicationNames[bundleID.lowercased()] ?? "Client")
        }
        if let terminal = terminalIdentity(routing.terminal) {
            return .application(terminal.name)
        }
        if nonempty(routing.workspacePath) != nil { return .finder }
        return nil
    }

    static func effectiveBundleID(_ routing: HyperliteAgentRouting) -> String? {
        if let bundleID = nonempty(routing.bundleID) { return bundleID }
        return terminalIdentity(routing.terminal)?.bundleID
    }

    private static let applicationNames = [
        "com.apple.terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm",
        "com.microsoft.vscode": "Visual Studio Code",
        "com.mitchellh.ghostty": "Ghostty",
        "com.openai.codex": "Codex",
        "com.anthropic.claudefordesktop": "Claude",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "dev.warp.warp-stable": "Warp",
    ]

    private static func terminalIdentity(_ value: String?) -> (name: String, bundleID: String)? {
        guard let value = nonempty(value) else { return nil }
        let key = value.lowercased()
        if key.contains("iterm") { return ("iTerm", "com.googlecode.iterm2") }
        if key.contains("apple_terminal") || key == "terminal" || key.contains("terminal.app") {
            return ("Terminal", "com.apple.Terminal")
        }
        if key.contains("warp") { return ("Warp", "dev.warp.Warp-Stable") }
        if key.contains("ghostty") { return ("Ghostty", "com.mitchellh.ghostty") }
        if key.contains("vscode") || key.contains("visual studio code") {
            return ("Visual Studio Code", "com.microsoft.VSCode")
        }
        return nil
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

enum HyperliteAgentDismissalPolicy {
    static func shouldSchedule(
        expanded: Bool,
        hasAutomaticDelay: Bool,
        pointerInside: Bool,
        editing: Bool,
        companionFocused: Bool
    ) -> Bool {
        expanded && hasAutomaticDelay && !pointerInside && !editing && !companionFocused
    }
}

enum HyperliteAgentNotchVisibilityPolicy {
    static func showsChrome(
        hasPhysicalNotch: Bool,
        expanded: Bool,
        pointerInside: Bool
    ) -> Bool {
        hasPhysicalNotch || expanded || pointerInside
    }

    static func showsShadow(hasPhysicalNotch: Bool, chromeVisible: Bool) -> Bool {
        !hasPhysicalNotch && chromeVisible
    }
}

enum HyperliteAgentAccessibilityPolicy {
    static func sessionLabel(_ session: HyperliteAgentSession) -> String {
        let attention = session.needsAttention ? ", needs attention" : ""
        return "\(session.displayTitle), \(session.profile), \(session.phase.label)\(attention)"
    }
}

struct HyperliteAgentActionSubmissionTracker: Equatable {
    private(set) var pending: Set<HyperliteAgentActionIdentity> = []

    mutating func begin(_ identity: HyperliteAgentActionIdentity) -> Bool {
        pending.insert(identity).inserted
    }

    mutating func remove(_ identity: HyperliteAgentActionIdentity) {
        pending.remove(identity)
    }

    mutating func retain(_ live: Set<HyperliteAgentActionIdentity>) {
        pending.formIntersection(live)
    }

    mutating func resolve(sessionID: String, requestID: String) {
        pending = pending.filter { $0.sessionID != sessionID || $0.requestID != requestID }
    }

    func contains(_ identity: HyperliteAgentActionIdentity) -> Bool {
        pending.contains(identity)
    }
}

enum HyperliteAgentAnswerResetPolicy {
    static func shouldReset(
        from previous: HyperliteAgentActionIdentity?,
        to current: HyperliteAgentActionIdentity?
    ) -> Bool {
        previous != current
    }
}

enum HyperliteAgentDiscoveryRefreshPolicy {
    static func shouldRefresh(
        lastRefresh: Date,
        now: Date,
        staleAfter: TimeInterval = 60
    ) -> Bool {
        now.timeIntervalSince(lastRefresh) >= staleAfter
    }
}

enum HyperliteAgentVerificationPolicy {
    static let timeoutSeconds: UInt64 = 10
}

enum HyperliteAgentSessionSelection {
    static func newestByID(
        _ sessions: [HyperliteAgentSession]
    ) -> [String: HyperliteAgentSession] {
        sessions.reduce(into: [:]) { values, session in
            guard let existing = values[session.id] else {
                values[session.id] = session
                return
            }
            if session.revision > existing.revision ||
                (session.revision == existing.revision && session.updatedAt > existing.updatedAt) {
                values[session.id] = session
            }
        }
    }
}

final class HyperliteAgentLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ incoming: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        data.append(incoming)
        if data.count > 2_097_152 {
            data.removeAll(keepingCapacity: false)
            return []
        }
        var lines: [Data] = []
        while let newline = data.firstIndex(of: 0x0A) {
            let line = Data(data[..<newline])
            data.removeSubrange(data.startIndex ... newline)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}
