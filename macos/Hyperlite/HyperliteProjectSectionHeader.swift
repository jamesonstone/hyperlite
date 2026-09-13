import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HyperliteProjectSectionHeader: View {
    let section: HyperliteProjectSection
    let chips: [HyperliteWorkflowChip]
    let compact: Bool
    @Binding var draggedRowID: String?
    let drop: (String) -> Void

    private var isIdle: Bool { section.rows.isEmpty }

    /// Chips the strip will actually render. Idle projects whose workflows are
    /// all quiet collapse to nothing in the compact layout, so no meaningless
    /// "+N" line survives next to "no open pull requests".
    private var stripChips: [HyperliteWorkflowChip] {
        compact
            ? HyperliteWorkflowStripPresentation.compactChips(chips).visible
            : chips
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [UTType.text.identifier],
                        delegate: HyperliteSectionPinDropDelegate(
                            draggedID: $draggedRowID,
                            pin: drop
                        )
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                HyperliteDashboardControlButton(
                    systemName: "arrow.triangle.pull",
                    active: false,
                    label: section.pullsButtonLabel,
                    disabled: section.pullsURL == nil
                ) { open(section.pullsURL) }
                HyperliteDashboardControlButton(
                    systemName: "play.circle",
                    active: chips.contains(where: \.isRunning),
                    label: section.actionsButtonLabel,
                    disabled: section.actionsURL == nil
                ) { open(section.actionsURL) }
            }
            if !stripChips.isEmpty {
                HyperliteWorkflowStrip(chips: chips, compact: compact)
            }
        }
        .padding(.top, isIdle ? 3 : 8)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(section.repository)
                .font(HyperliteTypography.heading)
                .foregroundStyle(
                    isIdle ? HyperliteTheme.mutedText.color : HyperliteTheme.primaryText.color
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if isIdle {
                Text(section.idleText)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(section.project.message ?? section.idleText)
            } else {
                Text("\(section.rows.count)")
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
            }
        }
    }

    private var accessibilityLabel: String {
        let lead = isIdle
            ? "\(section.repository) pull requests, \(section.idleText)"
            : "\(section.repository) pull requests, \(section.rows.count)"
        return lead + ", " +
            HyperliteWorkflowStripPresentation.headerSummary(chips: chips, now: Date())
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
