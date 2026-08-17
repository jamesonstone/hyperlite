import AppKit
import Foundation
import UserNotifications

@MainActor
enum HyperliteAgentAlerts {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func handle(
        previous: HyperliteAgentSessionSnapshot?,
        current: HyperliteAgentSessionSnapshot
    ) {
        let previousByID = Dictionary(uniqueKeysWithValues: (previous?.sessions ?? []).map { ($0.id, $0) })
        for session in current.sessions {
            let old = previousByID[session.id]
            if session.needsAttention, old?.needsAttention != true {
                alert(kind: "Agent needs attention", session: session)
            } else if (session.phase == .completed || session.phase == .error), old?.phase != session.phase {
                alert(kind: session.phase == .error ? "Agent session error" : "Agent session completed", session: session)
            }
        }
    }

    private static func alert(kind: String, session: HyperliteAgentSession) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "hyperlite.agent-session-sounds") {
            NSSound(named: "Ping")?.play()
        }
        guard defaults.bool(forKey: "hyperlite.agent-session-notifications") else { return }
        let content = UNMutableNotificationContent()
        content.title = kind
        content.body = "\(session.profile) · \(session.project)"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
