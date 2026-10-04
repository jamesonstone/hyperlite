import SwiftUI

/// VoiceOver copy for background GitHub work.
enum HyperliteOpenPRRefreshStatus {
    static let accessibilityRefreshing = "Refreshing open pull requests from GitHub"
    static let accessibilityPolling = "Polling GitHub Actions for running workflows"
}

/// The "Open PRs" title and count. A refresh shows only a small spinner here
/// so the ambient refresh never takes over the pane.
struct HyperliteOpenPRTitleCluster: View {
    let count: Int?
    var isRefreshing = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("Open PRs")
                .font(HyperliteTypography.title)
                .foregroundStyle(HyperliteTheme.primaryText.color)
            if let count {
                Text("\(count)")
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            }
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
        }
    }
}
