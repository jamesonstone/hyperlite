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
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 70)
        .help(workspace == .dashboard ? "Dashboard (⌘1)" : "Pinboard (⌘2)")
        .accessibilityLabel("Hyperlite workspace")
    }

    private var selection: Binding<HyperliteWorkspace> {
        Binding(get: { workspace }, set: onSelect)
    }
}
