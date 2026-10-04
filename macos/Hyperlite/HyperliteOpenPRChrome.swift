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
