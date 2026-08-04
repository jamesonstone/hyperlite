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

struct HyperlitePullRequestFilterPopover: View {
    @Binding var filter: HyperlitePullRequestFilter
    let repositories: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter Open PRs")
                .font(HyperliteTypography.semibold(11))
            TextField("Repository, title, or number", text: $filter.query)
                .textFieldStyle(.roundedBorder)
            Picker("Repository", selection: $filter.repository) {
                Text("All repositories").tag("")
                ForEach(repositories, id: \.self) { Text($0).tag($0) }
            }
            Picker("State", selection: $filter.state) {
                ForEach(HyperlitePullRequestStateFilter.allCases) {
                    Text($0.title).tag($0)
                }
            }
            Picker("Review", selection: $filter.review) {
                ForEach(HyperlitePullRequestReviewFilter.allCases) {
                    Text($0.title).tag($0)
                }
            }
            Picker("Data", selection: $filter.data) {
                ForEach(HyperlitePullRequestDataFilter.allCases) {
                    Text($0.title).tag($0)
                }
            }
            HStack {
                Spacer()
                Button("Clear") { filter = HyperlitePullRequestFilter() }
                    .disabled(!filter.isActive)
            }
        }
        .font(HyperliteTypography.regular(10))
        .pickerStyle(.menu)
        .padding(12)
        .frame(width: 300)
        .hyperliteTheme()
    }
}

struct HyperliteProjectFilterPopover: View {
    @Binding var filter: HyperliteProjectFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter Projects")
                .font(HyperliteTypography.semibold(11))
            TextField("Project, branch, or path", text: $filter.query)
                .textFieldStyle(.roundedBorder)
            Picker("Lane", selection: $filter.lane) {
                ForEach(HyperliteProjectLaneFilter.allCases) {
                    Text($0.title).tag($0)
                }
            }
            Picker("Activity", selection: $filter.activity) {
                ForEach(HyperliteProjectActivityFilter.allCases) {
                    Text($0.title).tag($0)
                }
            }
            HStack {
                Spacer()
                Button("Clear") { filter = HyperliteProjectFilter() }
                    .disabled(!filter.isActive)
            }
        }
        .font(HyperliteTypography.regular(10))
        .pickerStyle(.menu)
        .padding(12)
        .frame(width: 300)
        .hyperliteTheme()
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

struct HyperliteReorderAccessibilityModifier: ViewModifier {
    let enabled: Bool
    let id: String
    let moveBy: (String, Int) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAction(named: "Move up") { moveBy(id, -1) }
                .accessibilityAction(named: "Move down") { moveBy(id, 1) }
        } else {
            content
        }
    }
}
