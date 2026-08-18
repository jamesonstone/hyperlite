import SwiftUI

struct HyperliteAgentSessionSettings: View {
    @ObservedObject var state: HyperliteAgentSessionState
    @AppStorage("hyperlite.agent-session-sounds") private var agentSounds = false
    @AppStorage("hyperlite.agent-session-notifications") private var agentNotifications = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.hasConsent {
                Label(
                    "Review the detected integrations, then start Agent Sessions.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            integrationList
            HStack {
                Button("Check Again", action: state.refreshIntegrations)
                    .disabled(state.isDetectingIntegrations || state.isUpdatingIntegrations)
                if !state.hasConsent {
                    Button("Start Agent Sessions", action: state.completeOnboarding)
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                if state.isDetectingIntegrations || state.isUpdatingIntegrations {
                    ProgressView().controlSize(.small)
                }
            }
            HyperliteAgentIntegrationResults(
                successes: state.integrationSuccesses,
                failures: state.integrationFailures
            )
            Divider()
            Toggle("Play event sounds", isOn: $agentSounds)
            Toggle("Show metadata-only notifications", isOn: $agentNotifications)
                .onChange(of: agentNotifications) { enabled in
                    if enabled { HyperliteAgentAlerts.requestAuthorization() }
                }
            Text("Notifications include only the client profile and project name.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .onAppear {
            if state.integrations.isEmpty { state.refreshIntegrations() }
        }
    }

    @ViewBuilder
    private var integrationList: some View {
        if state.integrations.isEmpty, !state.isDetectingIntegrations {
            Text("No supported coding-agent clients were detected.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.integrations) { integration in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .center, spacing: 8) {
                            Toggle(isOn: integrationBinding(integration)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(integration.name)
                                            .font(.system(size: 12, weight: .medium))
                                        if !integration.detected {
                                            Text("Not Installed")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(integrationSummary(integration))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.switch)
                            .disabled(
                                (!integration.detected && !integration.enabled) ||
                                    state.isUpdatingIntegrations
                            )
                            .accessibilityLabel(Text(integration.name))
                            .accessibilityHint(Text(integrationSummary(integration)))
                            .accessibilityValue(Text(integration.enabled ? "Enabled" : "Disabled"))
                            if state.verifyingProfiles.contains(integration.id) {
                                ProgressView().controlSize(.small)
                            }
                            Button("Verify") { state.verifyIntegration(integration) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(
                                    !state.hasConsent || !integration.detected ||
                                        state.verifyingProfiles.contains(integration.id)
                                )
                                .accessibilityLabel("Verify \(integration.name) integration")
                        }
                        Text(healthSummary(integration))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    if integration.id != state.integrations.last?.id { Divider() }
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func integrationBinding(_ integration: HyperliteAgentIntegration) -> Binding<Bool> {
        Binding(
            get: {
                state.integrations.first(where: { $0.id == integration.id })?.enabled
                    ?? integration.enabled
            },
            set: { state.updateIntegration(integration, enabled: $0) }
        )
    }

    private func integrationSummary(_ integration: HyperliteAgentIntegration) -> String {
        if let message = integration.message, !message.isEmpty { return message }
        guard integration.detected else { return "Available when this client is installed." }
        switch integration.actionMode {
        case "blocking": return "Can present and respond to exact live requests."
        case "notify": return "Shows status and opens the owning client for action."
        case "observe": return "Observes lifecycle while preserving native permissions."
        default: return integration.actionMode.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func healthSummary(_ integration: HyperliteAgentIntegration) -> String {
        guard let health = state.integrationHealth[integration.id] else {
            return "Runtime health will appear after Agent Sessions starts."
        }
        var parts = [health.connectionState.replacingOccurrences(of: "_", with: " ").capitalized]
        if health.watchersLimit > 0 {
            parts.append("Watchers \(health.watchersUsed)/\(health.watchersLimit)")
        }
        if health.filteredCount > 0 { parts.append("Filtered \(health.filteredCount)") }
        if health.rejectedCount > 0 { parts.append("Rejected \(health.rejectedCount)") }
        if let result = health.selfTestResult, !result.isEmpty {
            parts.append("Verify \(result.capitalized)")
        }
        if let code = health.errorCode, !code.isEmpty { parts.append(code) }
        return parts.joined(separator: " · ")
    }
}

struct HyperliteAgentIntegrationResults: View {
    let successes: [String]
    let failures: [String: String]

    var body: some View {
        if !successes.isEmpty || !failures.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !successes.isEmpty {
                    Label(
                        "Updated: \(successes.joined(separator: ", "))",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(Color.green)
                }
                ForEach(failures.keys.sorted(), id: \.self) { identifier in
                    Label {
                        Text("\(identifier): \(failures[identifier] ?? "Unknown failure")")
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(Color.red)
                }
            }
            .font(.system(size: 10))
        }
    }
}
