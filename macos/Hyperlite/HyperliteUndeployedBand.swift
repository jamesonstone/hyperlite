import AppKit
import SwiftUI

/// Merged pull requests whose deploy did not run, above every organization.
/// Amber rather than red: it is a call to re-run a deploy, not a broken
/// build, and a faint tint keeps it findable without shouting.
enum HyperliteUndeployedStyle {
    static var tint: Color { HyperliteTheme.orange.color }
    static var background: Color { HyperliteTheme.orange.color.opacity(0.07) }
}

struct HyperliteUndeployedHeading: View {
    let projects: [HyperliteUndeployedProject]
    @Binding var collapsed: Bool

    var body: some View {
        Button {
            collapsed.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14)
                Text("🚀✕ NOT DEPLOYED")
                    .font(HyperliteTypography.semibold(HyperliteAppearance.shared.compactSize + 1))
                Text(HyperliteUndeployedPresentation.summary(projects))
                    .font(HyperliteTypography.compact)
                    .monospacedDigit()
                Rectangle().fill(HyperliteUndeployedStyle.tint.opacity(0.3)).frame(height: 1)
            }
            .foregroundStyle(HyperliteUndeployedStyle.tint)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? "Show merged pull requests that were not deployed" : "Hide the not-deployed list")
        .padding(.top, 10)
        .accessibilityLabel("Not deployed, \(HyperliteUndeployedPresentation.summary(projects))")
    }
}

struct HyperliteUndeployedProjectLine: View {
    let project: HyperliteUndeployedProject
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Button {
                open(project.runURL)
            } label: {
                HStack(spacing: 8) {
                    Text(project.section.repository)
                        .font(HyperliteTypography.body)
                        .foregroundStyle(HyperliteTheme.primaryText.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    ForEach(project.pipelines, id: \.file) { gap in
                        Text(HyperliteUndeployedPresentation.pipelineLabel(gap, now: now))
                            .foregroundStyle(HyperliteUndeployedStyle.tint)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let last = HyperliteUndeployedPresentation.lastDeployLabel(project.pipelines, now: now) {
                        Text(last)
                            .foregroundStyle(HyperliteTheme.mutedText.color)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Spacer(minLength: 4)
                }
                .font(HyperliteTypography.compact)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the deploy run on GitHub to re-run it")
            Button {
                open(project.runURL)
            } label: {
                Label("re-run", systemImage: "arrow.clockwise")
                    .labelStyle(HyperliteCompactLabelStyle())
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteUndeployedStyle.tint)
            }
            .buttonStyle(.plain)
            .disabled(project.runURL == nil)
            .help("Open the failed or skipped deploy run, where GitHub offers Re-run")
        }
        .padding(.leading, HyperlitePullRequestRowLayout.rowChromeLeading)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func open(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }
}

struct HyperliteUndeployedRow: View {
    let pullRequest: HyperliteUndeployedPullRequest
    let now: Date

    var body: some View {
        Button {
            if let url = pullRequest.url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 7) {
                Text(verbatim: "PR #\(pullRequest.number)")
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
                    .frame(width: HyperlitePullRequestRowLayout.pullRequestNumberColumnWidth, alignment: .leading)
                Text(HyperliteUndeployedPresentation.issueLabel(pullRequest) ?? "")
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
                    .frame(width: HyperlitePullRequestRowLayout.issueNumberColumnWidth, alignment: .leading)
                Text(HyperliteEmoji.render(pullRequest.title))
                    .foregroundStyle(HyperliteTheme.primaryText.color)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text("merged \(HyperlitePresentation.ageLabel(for: pullRequest.mergedAt, now: now))")
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteUndeployedStyle.tint)
                    .fixedSize()
            }
            .font(HyperliteTypography.body)
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pullRequest.url == nil)
        .padding(.leading, HyperlitePullRequestRowLayout.rowChromeLeading)
        .accessibilityLabel("Pull request \(pullRequest.number), \(pullRequest.title), merged, not deployed")
    }
}

/// Amber `🚀✕ N` on a project heading whose deploy is behind.
struct HyperliteDeployBehindBadge: View {
    let status: HyperliteDeployStatus

    var body: some View {
        Text(verbatim: "🚀✕\(HyperliteUndeployedPresentation.badgeCount(status))")
            .font(HyperliteTypography.semibold(HyperliteAppearance.shared.compactSize))
            .foregroundStyle(HyperliteUndeployedStyle.tint)
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(HyperliteUndeployedStyle.tint.opacity(0.15)))
            .lineLimit(1)
            .fixedSize()
            .help(HyperliteUndeployedPresentation.badgeHelp(status))
            .accessibilityLabel(HyperliteUndeployedPresentation.badgeHelp(status))
    }
}
