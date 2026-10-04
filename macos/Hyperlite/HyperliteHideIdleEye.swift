import SwiftUI

enum HyperliteHideIdlePresentation {
    static func hint(hideIdle: Bool, hiddenCount: Int) -> String {
        guard hideIdle else { return "Showing every project. Click to hide projects with no open pull requests." }
        let hidden = hiddenCount == 1 ? "1 project hidden" : "\(hiddenCount) projects hidden"
        return "\(hidden) with no open pull requests. Click to show all projects."
    }

    /// Hidden project names in list order, flagging ignored ones.
    static func hiddenNames(_ sections: [HyperliteProjectSection]) -> [String] {
        sections.map { $0.project.isIgnored ? "\($0.repository) (ignored)" : $0.repository }
    }
}

/// The global hide-idle eye. Hovering lists every hidden project so the
/// operator sees what the eye is hiding without expanding the quiet-ones list.
struct HyperliteHideIdleEye: View {
    @Binding var hideIdle: Bool
    let hiddenSections: [HyperliteProjectSection]
    @State private var hovering = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        HyperliteDashboardControlButton(
            systemName: hideIdle ? "eye.slash" : "eye",
            active: !hideIdle,
            label: HyperliteHideIdlePresentation.hint(hideIdle: hideIdle, hiddenCount: hiddenSections.count)
        ) { hideIdle.toggle() }
        .onHover { inside in
            hoverTask?.cancel()
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(inside ? 300 : 150))
                guard !Task.isCancelled else { return }
                hovering = inside && hideIdle && !hiddenSections.isEmpty
            }
        }
        .popover(isPresented: $hovering, arrowEdge: .bottom) { hiddenList }
    }

    private var hiddenList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(HyperliteHideIdlePresentation.hint(hideIdle: hideIdle, hiddenCount: hiddenSections.count))
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(HyperliteHideIdlePresentation.hiddenNames(hiddenSections), id: \.self) { name in
                        Text(name)
                            .font(HyperliteTypography.body)
                            .foregroundStyle(HyperliteTheme.secondaryText.color)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
        }
        .padding(12)
        .frame(width: 280)
        .background(HyperliteTheme.elevatedSurface.color)
    }
}
