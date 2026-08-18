import AppKit
import Combine
import Foundation

@MainActor
final class HyperliteAgentSessionState: ObservableObject {
    static let shared = HyperliteAgentSessionState()
    static let consentKey = "hyperlite.agent-integrations-consent"

    @Published private(set) var snapshot: HyperliteAgentSessionSnapshot?
    @Published private(set) var integrations: [HyperliteAgentIntegration] = []
    @Published private(set) var integrationHealth: [String: HyperliteAgentIntegrationHealth] = [:]
    @Published private(set) var processStatus: HyperliteAgentSessionProcess.Status = .stopped
    @Published private(set) var lastActionResult: HyperliteAgentActionResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var integrationFailures: [String: String] = [:]
    @Published private(set) var integrationSuccesses: [String] = []
    @Published private(set) var isUpdatingIntegrations = false
    @Published private(set) var isDetectingIntegrations = false
    @Published private(set) var verifyingProfiles: Set<String> = []
    @Published private(set) var integrationDetectionSucceeded = false
    @Published private(set) var hasConsent: Bool
    @Published private var actionSubmissions = HyperliteAgentActionSubmissionTracker()

    private let service: HyperliteAgentSessionProcess
    private var hasStarted = false
    private var lastDiscoveryRefreshAt = Date.distantPast

    init(service: HyperliteAgentSessionProcess? = nil) {
        let resolvedService = service ?? HyperliteAgentSessionProcess()
        self.service = resolvedService
        hasConsent = UserDefaults.standard.bool(forKey: Self.consentKey)
        resolvedService.onRecord = { [weak self] record in self?.receive(record) }
        resolvedService.onStatus = { [weak self] status in self?.processStatus = status }
    }

    func start() {
        guard HyperliteFeatureFlags.agentSessionPresentation, hasConsent, !hasStarted else { return }
        hasStarted = true
        service.start()
        lastDiscoveryRefreshAt = Date()
    }

    func prepareOnboarding() {
        guard HyperliteFeatureFlags.agentSessionPresentation, !hasConsent else { return }
        refreshIntegrations()
    }

    func stop() {
        hasStarted = false
        service.stop()
        snapshot = nil
        integrationHealth = [:]
        verifyingProfiles = []
        lastActionResult = nil
        actionSubmissions = .init()
    }

    func completeOnboarding() {
        guard !hasConsent else { return }
        UserDefaults.standard.set(true, forKey: Self.consentKey)
        hasConsent = true
        errorMessage = nil
        start()
    }

    func submit(
        _ action: String,
        for session: HyperliteAgentSession,
        answers: [String: [String]]? = nil
    ) {
        guard let pending = session.currentAction, let identity = session.actionIdentity else {
            errorMessage = "This request is no longer active."
            return
        }
        var submissions = actionSubmissions
        guard submissions.begin(identity) else { return }
        actionSubmissions = submissions
        let request = HyperliteAgentActionRequest(
            schema: snapshot?.schema == hyperliteAgentSnapshotSchemaV1 ?
                hyperliteAgentActionSchemaV1 : hyperliteAgentActionSchema,
            provider: session.provider,
            sessionID: session.id,
            requestID: pending.requestID,
            revision: identity.revision,
            action: action,
            answers: answers
        )
        do {
            try service.send(request)
            errorMessage = nil
        } catch {
            var submissions = actionSubmissions
            submissions.remove(identity)
            actionSubmissions = submissions
            errorMessage = error.localizedDescription
        }
    }

    func isSubmitting(_ session: HyperliteAgentSession) -> Bool {
        guard let identity = session.actionIdentity else { return false }
        return actionSubmissions.contains(identity)
    }

    func refreshSessions(manual: Bool = true) {
        guard hasStarted else { return }
        let operation = manual ? "manual_refresh" : "foreground_refresh"
        do {
            try service.send(HyperliteAgentControlRequest(
                operation: operation,
                profile: nil,
                requestID: nil
            ))
            lastDiscoveryRefreshAt = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSessionsIfStale(now: Date = Date()) {
        guard HyperliteAgentDiscoveryRefreshPolicy.shouldRefresh(
            lastRefresh: lastDiscoveryRefreshAt,
            now: now
        ) else { return }
        refreshSessions(manual: false)
    }

    func verifyIntegration(_ integration: HyperliteAgentIntegration) {
        guard hasStarted, !verifyingProfiles.contains(integration.id) else { return }
        verifyingProfiles.insert(integration.id)
        do {
            try service.send(HyperliteAgentControlRequest(
                operation: "integration_self_test",
                profile: integration.id,
                requestID: UUID().uuidString.lowercased()
            ))
        } catch {
            verifyingProfiles.remove(integration.id)
            errorMessage = error.localizedDescription
        }
    }

    func performRoute(_ session: HyperliteAgentSession) {
        if let bundleID = HyperliteAgentRoutePolicy.effectiveBundleID(session.routing) {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate(options: [])
                return
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                    guard let error else { return }
                    Task { @MainActor [weak self] in self?.errorMessage = error.localizedDescription }
                }
                return
            }
        }
        if let workspace = session.routing.workspacePath, !workspace.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace)])
            return
        }
        errorMessage = "The owning client could not be resolved."
    }

    func enableRecommendedIntegrations() {
        guard integrationDetectionSucceeded else {
            refreshIntegrations()
            return
        }
        let identifiers = integrations.filter(\.detected).map(\.id)
        guard !identifiers.isEmpty else {
            completeOnboarding()
            return
        }
        updateIntegrations(identifiers, action: "enable", grantsConsentOnSuccess: true)
    }

    func updateIntegration(_ integration: HyperliteAgentIntegration, enabled: Bool) {
        updateIntegrations([integration.id], action: enabled ? "enable" : "disable")
    }

    func refreshIntegrations() {
        guard !isDetectingIntegrations, !isUpdatingIntegrations else { return }
        isDetectingIntegrations = true
        Task { [weak self] in
            guard let self else { return }
            do {
                integrations = try await fetchIntegrations()
                integrationDetectionSucceeded = true
                integrationFailures = [:]
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isDetectingIntegrations = false
        }
    }

    private func updateIntegrations(
        _ identifiers: [String],
        action: String,
        grantsConsentOnSuccess: Bool = false
    ) {
        guard !isUpdatingIntegrations, !identifiers.isEmpty else { return }
        isUpdatingIntegrations = true
        integrationFailures = [:]
        integrationSuccesses = []
        Task { [weak self] in
            guard let self else { return }
            var failures: [String: String] = [:]
            var successes: [String] = []
            for identifier in identifiers {
                do {
                    _ = try await HyperliteProcess.run(
                        arguments: ["agent", "integrations", action, identifier],
                        operation: "\(action) \(identifier) integration"
                    )
                    successes.append(identifier)
                } catch {
                    failures[identifier] = error.localizedDescription
                }
            }
            do {
                integrations = try await fetchIntegrations()
                integrationDetectionSucceeded = true
            } catch {
                failures["refresh"] = error.localizedDescription
            }
            integrationFailures = failures
            integrationSuccesses = successes
            isUpdatingIntegrations = false
            let outcome = HyperliteAgentIntegrationOutcomePolicy.resolve(
                wasConsented: hasConsent,
                grantsConsentOnSuccess: grantsConsentOnSuccess,
                successfulMutations: successes.count,
                failedMutations: failures.count,
                refreshSucceeded: failures["refresh"] == nil
            )
            if failures.isEmpty { errorMessage = nil } else {
                errorMessage = "Some agent integrations could not be updated."
            }
            if outcome.shouldGrantConsent { completeOnboarding() }
            if outcome.shouldRestartService { restart() }
        }
    }

    private func fetchIntegrations() async throws -> [HyperliteAgentIntegration] {
        let data = try await HyperliteProcess.run(
            arguments: ["agent", "integrations", "list"],
            operation: "detect agent integrations"
        )
        return try JSONDecoder().decode([HyperliteAgentIntegration].self, from: data)
    }

    private func restart() {
        guard hasConsent else { return }
        snapshot = nil
        integrationHealth = [:]
        verifyingProfiles = []
        actionSubmissions = .init()
        service.restart()
        hasStarted = true
    }

    private func receive(_ record: HyperliteAgentWireRecord) {
        switch record {
        case let .snapshot(value):
            guard value.schema == hyperliteAgentSnapshotSchema ||
                    value.schema == hyperliteAgentSnapshotSchemaV1,
                  value.generation >= (snapshot?.generation ?? 0)
            else { return }
            let previous = snapshot
            snapshot = value
            integrations = value.integrations
            integrationDetectionSucceeded = true
            var submissions = actionSubmissions
            submissions.retain(Set(value.sessions.compactMap(\.actionIdentity)))
            actionSubmissions = submissions
            HyperliteAgentAlerts.handle(previous: previous, current: value)
            if integrationFailures.isEmpty { errorMessage = nil }
        case let .actionResult(value):
            guard value.schema == hyperliteAgentActionResultSchema else { return }
            lastActionResult = value
            var submissions = actionSubmissions
            submissions.resolve(sessionID: value.sessionID, requestID: value.requestID)
            actionSubmissions = submissions
            if value.status != "submitted" {
                errorMessage = value.message ?? "The agent action was rejected."
            }
        case let .health(value):
            guard value.schema == hyperliteAgentHealthSchema else { return }
            integrationHealth[value.profile] = value
            if value.selfTestResult != nil {
                verifyingProfiles.remove(value.profile)
            }
        }
    }
}
