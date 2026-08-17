import AppKit
import Combine
import Foundation

@MainActor
final class HyperliteAgentSessionState: ObservableObject {
    static let shared = HyperliteAgentSessionState()

    @Published private(set) var snapshot: HyperliteAgentSessionSnapshot?
    @Published private(set) var processStatus: HyperliteAgentSessionProcess.Status = .stopped
    @Published private(set) var lastActionResult: HyperliteAgentActionResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isUpdatingIntegrations = false

    private let service: HyperliteAgentSessionProcess
    private var hasStarted = false

    init(service: HyperliteAgentSessionProcess? = nil) {
        let resolvedService = service ?? HyperliteAgentSessionProcess()
        self.service = resolvedService
        resolvedService.onRecord = { [weak self] record in self?.receive(record) }
        resolvedService.onStatus = { [weak self] status in self?.processStatus = status }
    }

    func start() {
        guard HyperliteFeatureFlags.agentSessionPresentation, !hasStarted else { return }
        hasStarted = true
        service.start()
    }

    func stop() {
        hasStarted = false
        service.stop()
        snapshot = nil
        lastActionResult = nil
    }

    func submit(_ action: String, for session: HyperliteAgentSession, answers: [String: [String]]? = nil) {
        guard let pending = session.action else {
            errorMessage = "This request is no longer active."
            return
        }
        let request = HyperliteAgentActionRequest(
            sessionID: session.id,
            requestID: pending.requestID,
            revision: session.revision,
            action: action,
            answers: answers
        )
        do {
            try service.send(request)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInClient(_ session: HyperliteAgentSession) {
        if let bundleID = session.routing.bundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [])
            return
        }
        if let workspace = session.routing.workspacePath, !workspace.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace)])
            return
        }
        errorMessage = "The owning client could not be resolved."
    }

    func enableRecommendedIntegrations() {
        let identifiers = snapshot?.integrations.filter(\.detected).map(\.id) ?? []
        updateIntegrations(identifiers, action: "enable")
    }

    func updateIntegration(_ integration: HyperliteAgentIntegration, enabled: Bool) {
        updateIntegrations([integration.id], action: enabled ? "enable" : "disable")
    }

    private func updateIntegrations(_ identifiers: [String], action: String) {
        guard !isUpdatingIntegrations, !identifiers.isEmpty else { return }
        isUpdatingIntegrations = true
        Task { [weak self] in
            guard let self else { return }
            do {
                for identifier in identifiers {
                    _ = try await HyperliteProcess.run(
                        arguments: ["agent", "integrations", action, identifier],
                        operation: "\(action) \(identifier) integration"
                    )
                }
                UserDefaults.standard.set(true, forKey: "hyperlite.agent-integrations-consent")
                isUpdatingIntegrations = false
                restart()
            } catch {
                isUpdatingIntegrations = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restart() {
        service.stop()
        snapshot = nil
        service.start()
    }

    private func receive(_ record: HyperliteAgentWireRecord) {
        switch record {
        case let .snapshot(value):
            guard value.schema == hyperliteAgentSnapshotSchema,
                  value.generation >= (snapshot?.generation ?? 0)
            else { return }
            let previous = snapshot
            snapshot = value
            HyperliteAgentAlerts.handle(previous: previous, current: value)
            errorMessage = nil
        case let .actionResult(value):
            guard value.schema == hyperliteAgentActionResultSchema else { return }
            lastActionResult = value
            if value.status != "submitted" {
                errorMessage = value.message ?? "The agent action was rejected."
            }
        }
    }
}
