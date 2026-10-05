import AppKit
import SwiftUI

/// Quick facts in the top bar. Lower-priority facts drop first when the
/// window is narrow.
struct HyperliteQuickFactsBar: View {
    let facts: [HyperliteQuickFact]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: facts.count, through: 1, by: -1)), id: \.self) { count in
                row(Array(facts.prefix(count)))
            }
        }
    }

    private func row(_ shown: [HyperliteQuickFact]) -> some View {
        HStack(spacing: 12) {
            ForEach(shown) { fact in
                Text(fact.text)
                    .font(fact.id == "open" ? HyperliteTypography.sectionHeading : HyperliteTypography.compact)
                    .foregroundStyle(color(fact))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .help(fact.help)
            }
        }
    }

    private func color(_ fact: HyperliteQuickFact) -> Color {
        switch fact.tone {
        case .alert: HyperliteTheme.red.color
        case .attention: HyperliteTheme.orange.color
        case .neutral: fact.id == "open" ? HyperliteTheme.primaryText.color : HyperliteTheme.secondaryText.color
        }
    }
}

/// Last update on the left, Hyperlite version on the right.
struct HyperliteOpenPRFooter: View {
    let observedAt: Date?

    var body: some View {
        HStack {
            Text(HyperlitePullRequestPresentation.freshnessLabel(observedAt: observedAt))
            Spacer(minLength: 8)
            Text(HyperliteAppVersion.label(info: Bundle.main.infoDictionary ?? [:]))
        }
        .font(HyperliteTypography.compact)
        .foregroundStyle(HyperliteTheme.mutedText.color)
        .lineLimit(1)
        .padding(.top, 6)
    }
}

enum HyperliteAppVersion {
    /// `hyperlite v1.2.3 · abc1234` from the bundle, tolerating dev builds.
    static func label(info: [String: Any]) -> String {
        let version = (info["HyperliteDescribe"] as? String)
            ?? (info["CFBundleShortVersionString"] as? String)
            ?? "dev"
        let commit = (info["HyperliteCommit"] as? String) ?? ""
        let shown = version.first?.isNumber == true ? "v\(version)" : version
        return commit.isEmpty || version.contains(commit) ? "hyperlite \(shown)" : "hyperlite \(shown) · \(commit)"
    }
}

/// An organization's heading above its projects; opens the org on GitHub.
struct HyperliteOrganizationHeading: View {
    let group: HyperliteOrganizationGroup

    var body: some View {
        Button {
            if let url = group.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                Text(group.name)
                    .font(HyperliteTypography.semibold(HyperliteAppearance.shared.compactSize + 1))
                    .foregroundStyle(HyperliteTheme.cyan.color)
                    .textCase(.uppercase)
                Text(summary)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                Rectangle()
                    .fill(HyperliteTheme.mutedText.color.opacity(0.25))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(group.url == nil)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .accessibilityLabel("\(group.name) organization, \(summary)")
    }

    private var summary: String {
        let projects = group.sections.count
        let prs = group.pullRequestCount
        let projectText = "\(projects) project\(projects == 1 ? "" : "s")"
        return prs == 0 ? projectText : "\(prs) PR\(prs == 1 ? "" : "s") · \(projectText)"
    }
}

/// A spinner and label in the top bar while GitHub data is being fetched.
struct HyperliteRefreshBadge: View {
    var polling = false

    var body: some View {
        HStack(spacing: 5) {
            ProgressView().controlSize(.mini)
            Text(polling ? "checking workflows…" : "updating from GitHub…")
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.cyan.color)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(polling ? HyperliteOpenPRRefreshStatus.accessibilityPolling : HyperliteOpenPRRefreshStatus.accessibilityRefreshing)
    }
}

/// An indeterminate bar sweeping across the top of the list while fetching.
/// It lives in an overlay and animates only its own offset, so the list is
/// never re-laid out, and it exists only while a fetch is in flight.
struct HyperliteRefreshBar: View {
    @State private var phase: CGFloat = -0.35

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(HyperliteTheme.cyan.color.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(
                        colors: [.clear, HyperliteTheme.cyan.color, .clear],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: width * 0.35)
                    .offset(x: phase * width)
            }
        }
        .frame(height: 2)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

/// Separates every organization's open work from projects with nothing open.
struct HyperliteIdleDivider: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("NO OPEN PULL REQUESTS")
                .font(HyperliteTypography.semibold(HyperliteAppearance.shared.compactSize))
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Text("\(count) project\(count == 1 ? "" : "s")")
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Rectangle().fill(HyperliteTheme.mutedText.color.opacity(0.25)).frame(height: 1)
        }
        .padding(.top, 22)
        .accessibilityElement(children: .combine)
    }
}
