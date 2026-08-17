import SwiftUI

struct HyperliteAgentNotchView: View {
    @ObservedObject var state: HyperliteAgentSessionState
    let onExpansionChanged: (Bool) -> Void
    let onOpenWindow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var selectedID: String?
    @State private var dismissTask: Task<Void, Never>?

    private var sessions: [HyperliteAgentSession] { state.snapshot?.sessions ?? [] }
    private var selected: HyperliteAgentSession? {
        if let selectedID, let match = sessions.first(where: { $0.id == selectedID }) { return match }
        return sessions.first(where: \.needsAttention) ?? sessions.first
    }

    var body: some View {
        Group {
            if expanded { expandedContent } else { collapsedContent }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 18 : 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { setExpanded(true) } else if state.snapshot?.attentionCount == 0 { scheduleDismiss(after: 1) }
        }
        .onChange(of: state.snapshot?.generation) { _ in reactToSnapshot() }
        .onDisappear { dismissTask?.cancel() }
    }

    private var collapsedContent: some View {
        HStack(spacing: 8) {
            HyperliteGhostMark().frame(width: 15, height: 15)
            Label("\(state.snapshot?.activeCount ?? 0)", systemImage: "terminal.fill")
            if let attention = state.snapshot?.attentionCount, attention > 0 {
                Label("\(attention)", systemImage: "exclamationmark.bubble.fill")
                    .foregroundStyle(HyperliteTheme.orange.color)
            }
        }
        .font(HyperliteTypography.semibold(10))
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(collapsedAccessibilityLabel)
        .contentShape(Rectangle())
        .onTapGesture { setExpanded(true) }
    }

    private var collapsedAccessibilityLabel: String {
        "Hyperlite, \(state.snapshot?.activeCount ?? 0) active agent sessions, " +
            "\(state.snapshot?.attentionCount ?? 0) needing attention"
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Agent Sessions", systemImage: "terminal.fill")
                    .font(HyperliteTypography.semibold(12))
                Spacer()
                Button("Open Hyperlite") {
                    setExpanded(false)
                    onOpenWindow()
                }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button { setExpanded(false) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close agent sessions")
            }
            if sessions.isEmpty {
                Text("No current sessions. Open Hyperlite to configure detected integrations.")
                    .font(HyperliteTypography.regular(9))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 10) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(sessions) { session in
                            notchRow(session)
                                .onTapGesture { selectedID = session.id }
                        }
                    }
                }
                .frame(width: 132)
                Rectangle().fill(HyperliteTheme.elevatedSurface.color).frame(width: 1)
                if let selected {
                    HyperliteAgentSessionDetail(session: selected, state: state)
                } else {
                    Spacer()
                }
                }
            }
        }
        .padding(12)
    }

    private func notchRow(_ session: HyperliteAgentSession) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: session.phase.symbol)
                .foregroundStyle(session.needsAttention ? HyperliteTheme.orange.color : HyperliteTheme.secondaryText.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayTitle).font(HyperliteTypography.medium(8)).lineLimit(2)
                Text(session.phase.label)
                    .font(HyperliteTypography.regular(7))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected?.id == session.id ? HyperliteTheme.elevatedSurface.color : HyperliteTheme.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func reactToSnapshot() {
        guard let snapshot = state.snapshot else { return }
        if snapshot.attentionCount > 0 {
            setExpanded(true)
            scheduleDismiss(after: 12)
        } else if snapshot.sessions.contains(where: { $0.phase == .completed || $0.phase == .error }) {
            setExpanded(true)
            scheduleDismiss(after: 6)
        }
    }

    private func scheduleDismiss(after seconds: UInt64) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { setExpanded(false) }
        }
    }

    private func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        dismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expanded = value }
        onExpansionChanged(value)
    }
}
