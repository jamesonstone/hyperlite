import SwiftUI

struct HyperliteWorkspaceControl: View {
    let workspace: HyperliteWorkspace
    let onSelect: (HyperliteWorkspace) -> Void

    var body: some View {
        Picker("Workspace", selection: selection) {
            Label("Dashboard", systemImage: "rectangle.grid.1x2")
                .labelStyle(.iconOnly)
                .tag(HyperliteWorkspace.dashboard)
            Label("Pinboard", systemImage: "rectangle.3.group")
                .labelStyle(.iconOnly)
                .tag(HyperliteWorkspace.pinboard)
            if HyperliteFeatureFlags.agentSessionPresentation {
                Label("Agent Tasks", systemImage: "terminal.fill")
                    .labelStyle(.iconOnly)
                    .tag(HyperliteWorkspace.sessions)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: HyperliteFeatureFlags.agentSessionPresentation ? 96 : 70)
        .help(helpText)
        .accessibilityLabel("Hyperlite workspace")
    }

    private var selection: Binding<HyperliteWorkspace> {
        Binding(get: { workspace }, set: onSelect)
    }

    private var helpText: String {
        switch workspace {
        case .dashboard: "Dashboard (⌘1)"
        case .pinboard: "Pinboard (⌘2)"
        case .sessions: "Agent Tasks (⌘3)"
        }
    }
}
