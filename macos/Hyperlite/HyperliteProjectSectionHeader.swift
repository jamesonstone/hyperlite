import AppKit
import SwiftUI

struct HyperliteProjectSectionHeader: View {
    let section: HyperliteProjectSection
    let chips: [HyperliteWorkflowChip]
    var collapsed: Binding<Bool>? = nil
    var onToggleIgnore: (() -> Void)? = nil
    var stageKind: HyperliteOpenPRProjectStageKind = .active

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

    /// Two lines when there is pipeline status: the full repository name and
    /// count with the window actions, then a subheader of deploy badge,
    /// pipeline alerts, and workflow chips aligned under the name. The name has
    /// its own line, so it shows in full at any normal width; a crowded
    /// subheader clips at its right edge.
    var body: some View {
        VStack(alignment: .leading, spacing: HyperliteOpenPRSpacing.headingSubheaderSpacing) {
            titleLine
            if hasStatusCluster {
                statusCluster
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .padding(.leading, chromeLeading)
            }
        }
        .contentShape(Rectangle())
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            // Lantern and chevron share the rows' checkbox column, so the
            // repository name lines up with each row's PR number.
            HStack(spacing: 3) {
                lantern
                if let collapsed {
                    disclosureChevron(collapsed)
                }
            }
            .frame(width: chromeLeading - 6, alignment: .leading)
            Button {
                open(section.repositoryURL)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(section.repositoryURL == nil)
            .help(section.repositoryURL == nil ? section.repository : "Open \(section.repository) on GitHub")
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(section.repositoryURL == nil ? "" : "Opens the repository on GitHub")
            Spacer(minLength: 12)
            // The controls always stay on screen; only in a window too narrow
            // for the name does the name give way, truncating in the middle.
            HStack(spacing: 6) {
                if let onToggleIgnore {
                    ignoreButton(onToggleIgnore)
                }
                githubButtons
            }
            .fixedSize()
            .layoutPriority(2)
        }
    }

    private var deployStatus: HyperliteDeployStatus? {
        guard let deploys = section.project.workflows?.deploys, deploys.isBehind, !isIgnored else { return nil }
        return deploys
    }

    private var hasStatusCluster: Bool {
        !isIgnored && (deployStatus != nil || !pipelineAlerts.isEmpty || !stripChips.isEmpty)
    }

    /// The deploy badge, pipeline alerts, and workflow chips, set apart from
    /// the repository name and from each other so a busy heading stays legible.
    private var statusCluster: some View {
        HStack(spacing: HyperliteOpenPRSpacing.headingGroupSpacing) {
            if let deployStatus {
                HyperliteDeployBehindBadge(status: deployStatus)
                    .layoutPriority(3)
            }
            if !pipelineAlerts.isEmpty {
                HyperlitePipelineAlertStrip(alerts: pipelineAlerts)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }
            if !stripChips.isEmpty {
                HyperliteWorkflowStrip(chips: stripChips)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
    }

    /// The project's state at a glance: cyan while running, orange on a
    /// pipeline alert, quiet otherwise.
    private var lantern: some View {
        Capsule()
            .fill(
                stageKind.lanternUsesAttentionColor
                    ? HyperliteTheme.orange.color
                    : stageKind.lanternIsLive ? HyperliteTheme.cyan.color : HyperliteTheme.mutedText.color
            )
            .frame(width: 3, height: 16)
            .opacity(stageKind.lanternOpacity)
            .accessibilityHidden(true)
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
                .truncationMode(.middle)
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
                Text(verbatim: "\(section.rows.count)")
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
                    .lineLimit(1)
                    .fixedSize()
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

    /// The deploy badge replaces a deploy alert, so it is not shown twice.
    private var pipelineAlerts: [HyperlitePipelineAlert] {
        let alerts = HyperlitePipelineAlertPresentation.alerts(from: section.project.workflows)
        guard section.project.workflows?.deploys?.isBehind == true else { return alerts }
        return alerts.filter { $0.kind != "deploy" }
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
        case .active: HyperliteTheme.cyan.color
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
        if let deploys = section.project.workflows?.deploys, deploys.isBehind {
            parts.append(HyperliteUndeployedPresentation.badgeHelp(deploys))
        }
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
