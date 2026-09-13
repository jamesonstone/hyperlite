import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HyperliteProjectSectionHeader: View {
    let section: HyperliteProjectSection
    let chips: [HyperliteWorkflowChip]
    let compact: Bool
    @Binding var draggedRowID: String?
    let drop: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    open(section.repositoryURL)
                } label: {
                    HStack(spacing: 4) {
                        Text(section.repository)
                            .font(HyperliteTypography.heading)
                            .foregroundStyle(HyperliteTheme.secondaryText.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("\(section.rows.count)")
                            .font(HyperliteTypography.compact.monospacedDigit())
                            .foregroundStyle(HyperliteTheme.mutedText.color)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(section.repositoryURL == nil)
                .help(section.repositoryURL == nil ? "" : "Open \(section.repository) on GitHub")
                .frame(maxWidth: .infinity, alignment: .leading)
                .onDrop(
                    of: [UTType.text.identifier],
                    delegate: HyperliteSectionPinDropDelegate(
                        draggedID: $draggedRowID,
                        pin: drop
                    )
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(section.repositoryURL == nil ? "" : "Opens the repository on GitHub")
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
            if !chips.isEmpty {
                HyperliteWorkflowStrip(chips: chips, compact: compact)
            }
        }
        .padding(.top, 6)
    }

    private var accessibilityLabel: String {
        "\(section.repository) pull requests, \(section.rows.count), " +
            HyperliteWorkflowStripPresentation.headerSummary(chips: chips, now: Date())
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

struct HyperliteProjectIdleRow: View {
    let section: HyperliteProjectSection

    var body: some View {
        Text(section.idleText)
            .font(HyperliteTypography.compact)
            .foregroundStyle(HyperliteTheme.mutedText.color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(section.project.message ?? section.idleText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(section.repository), \(section.idleText)")
    }
}
