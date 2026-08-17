import SwiftUI

struct HyperliteAgentSessionsWorkspace: View {
    @ObservedObject var state: HyperliteAgentSessionState
    @AppStorage("hyperlite.agent-integrations-consent") private var hasConsent = false
    @State private var selectedID: String?
    @State private var customizing = false

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
            if !hasConsent {
                consent
            } else if customizing {
                integrations
            } else {
                sessionContent
            }
            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(HyperliteTheme.orange.color)
            }
        }
        .onAppear { state.start() }
        .onChange(of: sessions.map(\.id)) { ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = ids.first }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            Label("Agent Sessions", systemImage: "terminal.fill")
                .font(HyperliteTypography.semibold(14))
            Spacer()
            Text(statusText)
                .font(HyperliteTypography.regular(9))
                .foregroundStyle(HyperliteTheme.mutedText.color)
            if hasConsent {
                Button(customizing ? "Done" : "Integrations") { customizing.toggle() }
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

    private var consent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hyperlite can monitor detected coding agents through provider-owned hooks and local Codex interfaces.")
                .font(HyperliteTypography.regular(11))
                .fixedSize(horizontal: false, vertical: true)
            Text("Only Hyperlite-owned entries are maintained. Prompts, responses, transcripts, and raw hook payloads are never persisted.")
                .font(HyperliteTypography.regular(10))
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Enable Recommended Integrations") {
                    hasConsent = true
                    state.enableRecommendedIntegrations()
                }
                .buttonStyle(.borderedProminent)
                Button("Customize") {
                    hasConsent = true
                    customizing = true
                }
                .buttonStyle(.bordered)
                Button("Skip") { hasConsent = true }
                    .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(HyperliteTheme.elevatedSurface.color)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var integrations: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(state.snapshot?.integrations ?? []) { integration in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(integration.name).font(HyperliteTypography.medium(11))
                            Text(integration.detected ? integration.actionMode : "Not detected")
                                .font(HyperliteTypography.regular(9))
                                .foregroundStyle(HyperliteTheme.mutedText.color)
                        }
                        Spacer()
                        Toggle("", isOn: integrationBinding(integration))
                            .labelsHidden()
                            .disabled(!integration.detected || state.isUpdatingIntegrations)
                    }
                    .padding(8)
                    .background(HyperliteTheme.surface.color)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private var sessionContent: some View {
        HStack(alignment: .top, spacing: 12) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if sessions.isEmpty {
                        Text("No current agent sessions")
                            .font(HyperliteTypography.regular(10))
                            .foregroundStyle(HyperliteTheme.mutedText.color)
                    }
                    ForEach(sessions) { session in
                        HyperliteAgentSessionRow(session: session, selected: selected?.id == session.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedID = session.id }
                    }
                }
            }
            .frame(width: 190)
            Rectangle()
                .fill(HyperliteTheme.elevatedSurface.color)
                .frame(width: 1)
            if let selected {
                HyperliteAgentSessionDetail(session: selected, state: state)
            } else {
                Text("Select a live session")
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func integrationBinding(_ integration: HyperliteAgentIntegration) -> Binding<Bool> {
        Binding(
            get: { integration.enabled },
            set: { state.updateIntegration(integration, enabled: $0) }
        )
    }
}

private struct HyperliteAgentSessionRow: View {
    let session: HyperliteAgentSession
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: session.phase.symbol)
                .foregroundStyle(session.needsAttention ? HyperliteTheme.orange.color : HyperliteTheme.secondaryText.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(HyperliteTypography.medium(10))
                    .lineLimit(2)
                Text("\(session.profile) · \(session.phase.label)")
                    .font(HyperliteTypography.regular(8))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? HyperliteTheme.elevatedSurface.color : HyperliteTheme.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }
}
