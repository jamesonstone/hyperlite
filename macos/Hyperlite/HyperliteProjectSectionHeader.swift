import AppKit
import SwiftUI

struct HyperliteProjectSectionHeader: View {
    let section: HyperliteProjectSection
    let chips: [HyperliteWorkflowChip]
    var collapsed: Binding<Bool>? = nil
    var onToggleIgnore: (() -> Void)? = nil

    private var isIdle: Bool { section.rows.isEmpty }
    private var isIgnored: Bool { section.project.isIgnored }
    private var stripChips: [HyperliteWorkflowChip] {
        HyperliteProjectSectionChrome.stripChips(
            chips, idle: isIdle
        )
    }
    private var chromeLeading: CGFloat {
        HyperlitePullRequestRowLayout.rowChromeLeading
    }

    var body: some View {
        HStack(spacing: 6) {
            if let collapsed {
                disclosureChevron(collapsed)
            }
            Button {
                open(section.repositoryURL)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(section.repositoryURL == nil)
            .help(section.repositoryURL == nil ? "" : "Open \(section.repository) on GitHub")
            .padding(.leading, collapsed == nil ? chromeLeading : 0)
            .layoutPriority(0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(section.repositoryURL == nil ? "" : "Opens the repository on GitHub")
            if !pipelineAlerts.isEmpty && !isIgnored {
                HyperlitePipelineAlertStrip(alerts: pipelineAlerts)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }
            if !stripChips.isEmpty && !isIgnored {
                HyperliteWorkflowStrip(chips: stripChips)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            Spacer(minLength: 4)
            if let onToggleIgnore {
                ignoreButton(onToggleIgnore)
            }
            githubButtons
        }
        .contentShape(Rectangle())
        .padding(.top, isIdle
            ? HyperliteOpenPRSpacing.idleSectionTopPadding
            : HyperliteOpenPRSpacing.activeSectionTopPadding)
    }

    private func disclosureChevron(_ collapsed: Binding<Bool>) -> some View {
        Button {
            collapsed.wrappedValue.toggle()
        } label: {
            Image(systemName: collapsed.wrappedValue ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, chromeLeading - 20)
        .help(collapsed.wrappedValue ? "Show pull requests" : "Hide pull requests")
        .accessibilityLabel(
            collapsed.wrappedValue
                ? "Show \(section.repository) pull requests"
                : "Hide \(section.repository) pull requests"
        )
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(section.repository)
                .font(headingFont)
                .foregroundStyle(headingColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if isIgnored {
                Text(HyperliteProjectIgnorePresentation.ignoredText)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .lineLimit(1)
            } else if isIdle {
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

    private func ignoreButton(_ toggle: @escaping () -> Void) -> some View {
        HyperliteDashboardControlButton(
            systemName: HyperliteProjectIgnorePresentation.iconName(ignored: isIgnored),
            active: !isIgnored,
            label: HyperliteProjectIgnorePresentation.buttonLabel(
                repository: section.repository, ignored: isIgnored
            ),
            action: toggle
        )
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

    private var pipelineAlerts: [HyperlitePipelineAlert] {
        HyperlitePipelineAlertPresentation.alerts(from: section.project.workflows)
    }

    private var headingWeight: HyperliteProjectSectionChrome.HeadingWeight {
        HyperliteProjectSectionChrome.headingWeight(
            idle: isIdle, chips: chips, alerts: pipelineAlerts
        )
    }

    private var headingFont: Font {
        switch headingWeight {
        case .active: HyperliteTypography.sectionHeading
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
        if isIgnored {
            return "\(section.repository), \(HyperliteProjectIgnorePresentation.ignoredText)"
        }
        let lead = isIdle
            ? "\(section.repository) pull requests, \(section.idleText)"
            : "\(section.repository) pull requests, \(section.rows.count)"
        var parts = [lead, HyperliteWorkflowStripPresentation.headerSummary(chips: chips, now: Date())]
        if !pipelineAlerts.isEmpty {
            parts.append(pipelineAlerts.map(HyperlitePipelineAlertPresentation.accessibilityLabel).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
