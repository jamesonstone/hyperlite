import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HyperliteProjectSectionHeader: View {
    let section: HyperliteProjectSection
    let chips: [HyperliteWorkflowChip]
    let compact: Bool
    var celestialKind: HyperliteProjectCelestialKind = .star
    @Binding var draggedRowID: String?
    let drop: (String) -> Void
    @State private var headingHovering = false

    private var isIdle: Bool { section.rows.isEmpty }
    private var stripChips: [HyperliteWorkflowChip] {
        HyperliteProjectSectionChrome.stripChips(
            chips, idle: isIdle, compact: compact
        )
    }
    private var chromeLeading: CGFloat {
        HyperlitePullRequestRowLayout.rowChromeLeading
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                open(section.repositoryURL)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(section.repositoryURL == nil)
            .help(section.repositoryURL == nil ? "" : "Open \(section.repository) on GitHub")
            .padding(.leading, chromeLeading)
            .layoutPriority(0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(section.repositoryURL == nil ? "" : "Opens the repository on GitHub")
            if !stripChips.isEmpty {
                HyperliteWorkflowStrip(chips: stripChips, compact: false)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            Spacer(minLength: 4)
            if !compact {
                githubButtons
            }
        }
        .overlay(alignment: .trailing) {
            if compact {
                githubButtons
                    .opacity(headingHovering ? 1 : 0)
                    .allowsHitTesting(headingHovering)
            }
        }
        .contentShape(Rectangle())
        .onHover { headingHovering = $0 }
        .onDrop(
            of: [UTType.text.identifier],
            delegate: HyperliteSectionPinDropDelegate(
                draggedID: $draggedRowID,
                pin: drop
            )
        )
        .padding(.top, isIdle
            ? HyperliteWorkspaceSplit.stackedIdleSectionTopPadding
            : HyperliteWorkspaceSplit.stackedActiveSectionTopPadding)
    }

    private var label: some View {
        HStack(spacing: 6) {
            HyperliteProjectCelestialIcon(
                kind: celestialKind,
                id: section.project.id
            )
            Text(compact
                ? HyperliteHiddenProjectGhostSkyPresentation.shortName(section.repository)
                : section.repository)
                .font(headingFont)
                .foregroundStyle(headingColor)
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

    private var githubButtons: some View {
        HStack(spacing: 4) {
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
    }

    private var headingWeight: HyperliteProjectSectionChrome.HeadingWeight {
        HyperliteProjectSectionChrome.headingWeight(idle: isIdle, chips: chips)
    }

    private var headingFont: Font {
        switch headingWeight {
        case .active: HyperliteTypography.heading
        case .notable: HyperliteTypography.body
        case .idle: HyperliteTypography.compact
        }
    }

    private var headingColor: Color {
        switch headingWeight {
        case .active: HyperliteTheme.primaryText.color
        case .notable: HyperliteTheme.secondaryText.color
        case .idle: HyperliteTheme.mutedText.color
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
