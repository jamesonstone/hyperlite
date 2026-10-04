import SwiftUI

struct HyperliteDashboardHeaderIcon: View {
    let systemName: String
    let active: Bool

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(
                active ? HyperliteTheme.cyan.color : HyperliteTheme.mutedText.color
            )
            .frame(width: 20, height: 18)
            .contentShape(Rectangle())
    }
}

struct HyperliteDashboardControlButton: View {
    let systemName: String
    let active: Bool
    let label: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HyperliteDashboardHeaderIcon(systemName: systemName, active: active)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct HyperliteReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggedID: String?
    let move: (String, String) -> Void

    func dropEntered(info _: DropInfo) {
        guard let draggedID, draggedID != targetID else { return }
        move(draggedID, targetID)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func dropExited(info _: DropInfo) {}
}
