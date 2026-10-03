import SwiftUI

/// A running workflow: a still cyan dot, the workflow title, and elapsed time
/// that ticks once a second.
struct HyperliteRunningWorkflowChip: View {
    let title: String
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 4) {
                Circle()
                    .fill(HyperliteTheme.cyan.color)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(title)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.cyan.color)
                    .lineLimit(1)
                Text(HyperliteWorkflowStripPresentation.elapsedLabel(since: since, now: context.date))
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .lineLimit(1)
            }
        }
        .transaction { $0.animation = nil }
    }
}
