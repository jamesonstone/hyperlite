import SwiftUI

enum HyperliteHideIdlePresentation {
    static func hint(hideIdle: Bool, hiddenCount: Int) -> String {
        guard hideIdle else { return "Showing every project. Click to hide projects with no open pull requests." }
        let hidden = hiddenCount == 1 ? "1 project hidden" : "\(hiddenCount) projects hidden"
        return "\(hidden) with no open pull requests. Click to show all projects."
    }

    /// Every project grouped by organization for the eye's hover list.
    static func groups(_ sections: [HyperliteProjectSection]) -> [HyperliteOrganizationGroup] {
        let sorted = sections.sorted {
            $0.repository.localizedCaseInsensitiveCompare($1.repository) == .orderedAscending
        }
        return HyperliteOrganizationGroup.groups(sorted).sorted { $0.name < $1.name }
    }

    static func watchLabel(repository: String, ignored: Bool) -> String {
        ignored ? "\(repository) is ignored. Click to watch it." : "\(repository) is watched. Click to ignore it."
    }
}

/// The global hide-idle eye. Click toggles hiding projects without open pull
/// requests. Hovering lists every project by organization with its own eye
/// (blue open = watched, gray closed = ignored); clicking one toggles ignore.
/// The list stays open while the pointer is over the eye or the list.
struct HyperliteHideIdleEye: View {
    @Binding var hideIdle: Bool
    let sections: [HyperliteProjectSection]
    let hiddenCount: Int
    var onToggleIgnore: (HyperliteProjectPullRequests) -> Void = { _ in }
    @State private var presented = false
    @State private var eyeHovering = false
    @State private var listHovering = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button { hideIdle.toggle() } label: {
            HyperliteDashboardHeaderIcon(systemName: hideIdle ? "eye.slash" : "eye", active: !hideIdle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HyperliteHideIdlePresentation.hint(hideIdle: hideIdle, hiddenCount: hiddenCount))
        .onHover { inside in
            eyeHovering = inside
            inside ? scheduleOpen() : scheduleClose()
        }
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            projectList
                .onHover { inside in
                    listHovering = inside
                    if !inside { scheduleClose() }
                }
                .onDisappear { listHovering = false }
        }
    }

    private func scheduleOpen() {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, eyeHovering, !sections.isEmpty else { return }
            presented = true
        }
    }

    private func scheduleClose() {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: HyperlitePullRequestHoverPresentation.closeGrace)
            guard !Task.isCancelled, !eyeHovering, !listHovering else { return }
            presented = false
        }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(HyperliteHideIdlePresentation.hint(hideIdle: hideIdle, hiddenCount: hiddenCount))
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(HyperliteHideIdlePresentation.groups(sections)) { group in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name.uppercased())
                                .font(HyperliteTypography.semibold(HyperliteAppearance.shared.compactSize))
                                .foregroundStyle(HyperliteTheme.cyan.color)
                            ForEach(group.sections) { section in projectRow(section) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 380)
        }
        .padding(12)
        .frame(width: 340)
        .background(HyperliteTheme.elevatedSurface.color)
    }

    private func projectRow(_ section: HyperliteProjectSection) -> some View {
        let ignored = section.project.isIgnored
        return HStack(spacing: 8) {
            Button { onToggleIgnore(section.project) } label: {
                Image(systemName: ignored ? "eye.slash" : "eye")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ignored ? HyperliteTheme.mutedText.color : HyperliteTheme.blue.color)
                    .frame(width: 18, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(HyperliteHideIdlePresentation.watchLabel(repository: section.repository, ignored: ignored))
            Text(shortName(section.repository))
                .font(HyperliteTypography.body)
                .foregroundStyle(ignored ? HyperliteTheme.mutedText.color : HyperliteTheme.secondaryText.color)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if !section.rows.isEmpty {
                Text("\(section.rows.count)")
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            }
        }
    }

    private func shortName(_ repository: String) -> String {
        repository.split(separator: "/", maxSplits: 1).last.map(String.init) ?? repository
    }
}
