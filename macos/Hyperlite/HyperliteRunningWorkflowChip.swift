import SwiftUI

/// A running workflow: a still cyan dot, the workflow title, and elapsed time
/// that ticks once a second while the window is visible. The elapsed label has
/// a fixed width so a tick never changes the chip's size and never re-lays out
/// the list around it.
struct HyperliteRunningWorkflowChip: View {
    let title: String
    let since: Date
    @Environment(\.hyperliteWindowVisible) private var windowVisible

    static let elapsedLabelWidth: CGFloat = 52

    var body: some View {
        TimelineView(HyperliteVisibleTickSchedule(visible: windowVisible)) { context in
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
                    .frame(width: Self.elapsedLabelWidth, alignment: .leading)
            }
        }
        .transaction { $0.animation = nil }
    }
}

/// Ticks every second while visible and never while hidden, so an occluded or
/// closed window spends no timer wakeups or renders on elapsed labels.
struct HyperliteVisibleTickSchedule: TimelineSchedule {
    let visible: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard visible else {
            var emitted = false
            return AnyIterator {
                defer { emitted = true }
                return emitted ? nil : startDate
            }
        }
        var next = startDate
        return AnyIterator {
            defer { next = next.addingTimeInterval(1) }
            return next
        }
    }
}

private struct HyperliteWindowVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the main window is on screen; drives tick schedules.
    var hyperliteWindowVisible: Bool {
        get { self[HyperliteWindowVisibleKey.self] }
        set { self[HyperliteWindowVisibleKey.self] = newValue }
    }
}
