import SwiftUI

struct HyperliteAgentSessionsWorkspace: View {
    @ObservedObject var state: HyperliteAgentSessionState
    @State private var selectedID: String?

    private var sessions: [HyperliteAgentSession] { state.snapshot?.sessions ?? [] }
    private var selected: HyperliteAgentSession? {
        if let selectedID, let match = sessions.first(where: { $0.id == selectedID }) {
            return match
        }
        return sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            if state.hasConsent { sessionContent } else { welcome }
            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .textSelection(.enabled)
            }
            HyperliteAgentIntegrationResults(
                successes: state.integrationSuccesses,
                failures: state.integrationFailures
            )
        }
        .font(.system(size: 13))
        .onAppear {
            if state.hasConsent { state.start() } else { state.prepareOnboarding() }
            if selectedID == nil { selectedID = sessions.first?.id }
        }
        .onChange(of: sessions.map(\.id)) { ids in
            if selectedID == nil || !ids.contains(selectedID ?? "") {
                selectedID = ids.first
            }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            Label("Agent Sessions", systemImage: "terminal.fill")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if state.hasConsent {
                Label(statusText, systemImage: statusSymbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Manage Integrations…", action: openHyperliteSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var statusText: String {
        switch state.processStatus {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Live"
        case .unavailable: "Unavailable"
        }
    }

    private var statusSymbol: String {
        switch state.processStatus {
        case .stopped: "stop.circle"
        case .starting: "hourglass"
        case .running: "circle.fill"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(spacing: 7) {
                Text("Keep an eye on your coding agents")
                    .font(.system(size: 18, weight: .semibold))
                Text(
                    "Hyperlite can show live status and route exact approval or input requests. " +
                        "Session content stays in memory and integration changes require your choice."
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            if state.isDetectingIntegrations {
                ProgressView("Looking for installed coding agents…")
                    .controlSize(.small)
            } else {
                VStack(spacing: 8) {
                    Button(
                        state.integrationDetectionSucceeded ? "Enable Recommended" : "Try Detection Again",
                        action: state.enableRecommendedIntegrations
                    )
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(state.isUpdatingIntegrations)
                    HStack(spacing: 14) {
                        Button("Review in Settings") {
                            state.refreshIntegrations()
                            openHyperliteSettings()
                        }
                        .buttonStyle(.link)
                        Button("Not Now", action: state.completeOnboarding)
                            .buttonStyle(.link)
                    }
                }
            }
            Text("Only Hyperlite-owned configuration entries are maintained.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 430)
        .padding(28)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var sessionContent: some View {
        HStack(alignment: .top, spacing: 12) {
            if sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("No Current Sessions")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Sessions appear here while supported coding agents are active.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sessions, selection: $selectedID) { session in
                    HyperliteAgentSessionRow(session: session)
                        .tag(session.id)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(width: 190)
                Divider()
                if let selected {
                    HyperliteAgentSessionDetail(session: selected, state: state)
                }
            }
        }
    }
}

struct HyperliteAgentSessionRow: View {
    let session: HyperliteAgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: session.phase.symbol)
                .foregroundStyle(session.needsAttention ? Color.orange : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                Text("\(session.profile) · \(session.phase.label)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(HyperliteAgentAccessibilityPolicy.sessionLabel(session))
    }
}
