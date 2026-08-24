import SwiftUI

struct HyperliteAgentNotchView: View {
    @ObservedObject var state: HyperliteAgentSessionState
    @ObservedObject var display: HyperliteAgentNotchDisplayState
    let onExpansionChanged: (Bool, Bool) -> Void
    let onHoverChanged: (Bool) -> Void
    let onRequestFocus: () -> Void
    let onOpenWindow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var selectedID: String?
    @State private var programmaticSelectionID: String?
    @State private var dismissTask: Task<Void, Never>?
    @State private var lastSnapshot: HyperliteAgentSessionSnapshot?
    @State private var autoDismissDelay: UInt64?
    @State private var pointerInside = false
    @State private var editing = false

    private var sessions: [HyperliteAgentSession] {
        (state.snapshot?.sessions ?? []).filter { !$0.synthetic }
    }
    private var activeCount: Int { sessions.filter { $0.phase.isActive }.count }
    private var attentionCount: Int { sessions.filter(\.needsAttention).count }
    private var selected: HyperliteAgentSession? {
        if let selectedID, let match = sessions.first(where: { $0.id == selectedID }) { return match }
        return sessions.first(where: \.needsAttention) ?? sessions.first
    }
    private var showsChrome: Bool {
        HyperliteAgentNotchVisibilityPolicy.showsChrome(
            hasPhysicalNotch: display.hasPhysicalNotch,
            expanded: expanded,
            pointerInside: pointerInside
        )
    }

    var body: some View {
        Group {
            if expanded { expandedContent } else { collapsedContent }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { notchBackground }
        .overlay {
            if !display.hasPhysicalNotch {
                RoundedRectangle(cornerRadius: expanded ? 16 : 11, style: .continuous)
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    .opacity(showsChrome ? 1 : 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 16 : 11, style: .continuous))
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsChrome)
        .onHover { hovering in
            pointerInside = hovering
            onHoverChanged(hovering)
            guard expanded else { return }
            if hovering { cancelDismiss() } else { resumeAutoDismissIfIdle() }
        }
        .onChange(of: state.snapshot?.generation) { _ in reactToSnapshot() }
        .onChange(of: display.hasCompanionFocus) { focused in
            if focused { cancelDismiss() } else { resumeAutoDismissIfIdle() }
        }
        .onChange(of: sessions.map(\.id)) { identifiers in
            if selectedID == nil || !identifiers.contains(selectedID ?? "") {
                selectProgrammatically(sessions.first(where: \.needsAttention)?.id ?? identifiers.first)
            }
        }
        .onAppear {
            selectProgrammatically(sessions.first(where: \.needsAttention)?.id ?? sessions.first?.id)
            reactToSnapshot()
        }
        .onDisappear {
            dismissTask?.cancel()
            onHoverChanged(false)
        }
    }

    @ViewBuilder
    private var notchBackground: some View {
        if display.hasPhysicalNotch {
            Color.black
        } else {
            Rectangle().fill(.regularMaterial)
                .overlay(Color.black.opacity(0.18))
                .opacity(showsChrome ? 1 : 0)
        }
    }

    private var collapsedContent: some View {
        Button(action: expandManually) {
            HStack(spacing: 8) {
                HyperliteGhostMark().frame(width: 15, height: 15)
                Label("\(activeCount)", systemImage: "terminal.fill")
                if attentionCount > 0 {
                    Label("\(attentionCount)", systemImage: "exclamationmark.bubble.fill")
                        .foregroundStyle(Color.orange)
                }
            }
            .opacity(showsChrome ? 1 : 0)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsedAccessibilityLabel)
        .help("Show Agent Tasks")
    }

    private var collapsedAccessibilityLabel: String {
        "Hyperlite, \(activeCount) active agent sessions, " +
            "\(attentionCount) needing attention"
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Agent Tasks", systemImage: "terminal.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Open Hyperlite") {
                    recordInteraction()
                    setExpanded(false)
                    onOpenWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button { setExpanded(false) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Close Agent Tasks")
            }
            if sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Active Agent Tasks")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Open Hyperlite to review detected integrations.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    List(sessions, selection: $selectedID) { session in
                        HyperliteAgentNotchRow(session: session)
                            .tag(session.id)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .frame(width: 145)
                    Divider()
                    if let selected {
                        HyperliteAgentSessionDetail(
                            session: selected,
                            state: state,
                            onInteraction: { recordInteraction() },
                            onEditingChanged: editingChanged
                        )
                    } else {
                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .simultaneousGesture(TapGesture().onEnded { recordInteraction() })
        .onChange(of: selectedID) { identifier in
            let wasProgrammatic = programmaticSelectionID == identifier
            programmaticSelectionID = nil
            recordInteraction(requestFocus: !wasProgrammatic)
        }
    }

    private func reactToSnapshot() {
        guard let snapshot = state.snapshot else { return }
        let transition = snapshot.popupTransition(from: lastSnapshot)
        lastSnapshot = snapshot
        guard let transition else { return }
        autoDismissDelay = transition.dismissDelay
        setExpanded(true, activate: false)
        resumeAutoDismissIfIdle()
    }

    private func expandManually() {
        autoDismissDelay = nil
        setExpanded(true, activate: true)
    }

    private func editingChanged(_ active: Bool) {
        editing = active
        if active {
            onRequestFocus()
            cancelDismiss()
        } else {
            resumeAutoDismissIfIdle()
        }
    }

    private func selectProgrammatically(_ identifier: String?) {
        programmaticSelectionID = identifier
        selectedID = identifier
    }

    private func recordInteraction(requestFocus: Bool = true) {
        if requestFocus { onRequestFocus() }
        cancelDismiss()
        resumeAutoDismissIfIdle()
    }

    private func resumeAutoDismissIfIdle() {
        guard HyperliteAgentDismissalPolicy.shouldSchedule(
            expanded: expanded,
            hasAutomaticDelay: autoDismissDelay != nil,
            pointerInside: pointerInside,
            editing: editing,
            companionFocused: display.hasCompanionFocus
        ), let delay = autoDismissDelay else { return }
        scheduleDismiss(after: delay)
    }

    private func scheduleDismiss(after seconds: UInt64) {
        cancelDismiss()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { setExpanded(false) }
        }
    }

    private func cancelDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func setExpanded(_ value: Bool, activate: Bool = false) {
        cancelDismiss()
        guard value != expanded else { return }
        if !value { autoDismissDelay = nil }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expanded = value }
        onExpansionChanged(value, activate)
    }
}

private struct HyperliteAgentNotchRow: View {
    let session: HyperliteAgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: session.phase.symbol)
                .foregroundStyle(session.needsAttention ? Color.orange : Color.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                Text(session.phase.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(HyperliteAgentAccessibilityPolicy.sessionLabel(session))
    }
}
