import SwiftUI

/// Wall-clock math for the gliding ghost under a running workflow chip. Like
/// the refresh ghost, it ticks at a low rate only while something is running.
enum HyperliteWorkflowRunGlide {
    static let glyph = "👻"
    static let tickInterval: TimeInterval = 1.0 / 12.0
    static let period: TimeInterval = 2.6
    static let trackHeight: CGFloat = 3
    static let trackWidth: CGFloat = 80
    static let glyphSize: CGFloat = 9
    static let accessibilityPolling = "Polling GitHub Actions for running workflows"

    static func phase(at date: Date) -> Double {
        var elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        if elapsed < 0 { elapsed += period }
        return elapsed / period
    }

    /// Ping-pong progress with an ease at each end so the ghost turns around
    /// instead of snapping.
    static func progress(at date: Date) -> Double {
        let phase = phase(at: date)
        let raw = phase < 0.5 ? phase * 2 : 2 - phase * 2
        return raw * raw * (3 - 2 * raw)
    }

    static func facesRight(at date: Date) -> Bool {
        phase(at: date) < 0.5
    }

    static func ghostOffset(at date: Date, trackWidth: CGFloat, glyphWidth: CGFloat) -> CGFloat {
        max(0, trackWidth - glyphWidth) * progress(at: date)
    }

    static func showsGlide(_ state: HyperliteWorkflowChipState) -> Bool {
        if case .running = state { return true }
        return false
    }
}

struct HyperliteRunningWorkflowChip: View {
    let title: String
    let since: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            staticIndicator
        } else {
            TimelineView(.periodic(from: .now, by: HyperliteWorkflowRunGlide.tickInterval)) { context in
                content(now: context.date) {
                    HyperliteWorkflowRunGlideTrack(date: context.date)
                        .frame(width: HyperliteWorkflowRunGlide.trackWidth)
                }
            }
            .transaction { $0.animation = nil }
        }
    }

    // Reduce Motion replaces the gliding ghost with a still cyan dot so the
    // chip still reads as running without animation.
    private var staticIndicator: some View {
        content(now: Date()) {
            Circle()
                .fill(HyperliteTheme.cyan.color)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
        }
    }

    private func content(now: Date, @ViewBuilder track: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(title)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.cyan.color)
                    .lineLimit(1)
                Text(HyperliteWorkflowStripPresentation.elapsedLabel(since: since, now: now))
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .lineLimit(1)
            }
            track()
        }
    }
}

struct HyperliteWorkflowRunGlideTrack: View {
    let date: Date

    var body: some View {
        GeometryReader { geo in
            let glyphWidth = HyperliteWorkflowRunGlide.glyphSize + 2
            let offset = HyperliteWorkflowRunGlide.ghostOffset(
                at: date, trackWidth: geo.size.width, glyphWidth: glyphWidth
            )
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(HyperliteTheme.elevatedSurface.color)
                    .frame(height: HyperliteWorkflowRunGlide.trackHeight)
                Capsule()
                    .fill(HyperliteTheme.cyan.color.opacity(0.35))
                    .frame(width: offset + glyphWidth / 2, height: HyperliteWorkflowRunGlide.trackHeight)
                Text(HyperliteWorkflowRunGlide.glyph)
                    .font(.system(size: HyperliteWorkflowRunGlide.glyphSize))
                    .scaleEffect(x: HyperliteWorkflowRunGlide.facesRight(at: date) ? 1 : -1, y: 1)
                    .offset(x: offset, y: -HyperliteWorkflowRunGlide.glyphSize / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: HyperliteWorkflowRunGlide.glyphSize + 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
