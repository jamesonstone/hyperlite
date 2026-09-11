import SwiftUI

enum HyperliteOpenPRRefreshPulse {
    static let glyph = "👻"
    static let accessibilityRefreshing = "Refreshing open pull requests from GitHub"
    static let spinDuration: TimeInterval = 1.15
    static let pauseDuration: TimeInterval = 0.4
    static let tickInterval: TimeInterval = 1.0 / 12.0
    static let overlayOpacity: Double = 0.36
    static let fillRatio: CGFloat = 0.68

    static var cycleDuration: TimeInterval { spinDuration + pauseDuration }

    static func rotationDegrees(isRefreshing: Bool, at date: Date) -> Double {
        guard isRefreshing else { return 0 }
        var elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration)
        if elapsed < 0 { elapsed += cycleDuration }
        if elapsed >= spinDuration { return 0 }
        return (elapsed / spinDuration) * 360
    }

    static func showsOverlay(_ isRefreshing: Bool) -> Bool {
        isRefreshing
    }
}

struct HyperliteOpenPRRefreshGhostOverlay: View {
    let isRefreshing: Bool

    var body: some View {
        Group {
            if HyperliteOpenPRRefreshPulse.showsOverlay(isRefreshing) {
                TimelineView(
                    .periodic(
                        from: .now,
                        by: HyperliteOpenPRRefreshPulse.tickInterval
                    )
                ) { context in
                    GeometryReader { geo in
                        let side = min(geo.size.width, geo.size.height)
                        Text(HyperliteOpenPRRefreshPulse.glyph)
                            .font(.system(size: side * HyperliteOpenPRRefreshPulse.fillRatio))
                            .opacity(HyperliteOpenPRRefreshPulse.overlayOpacity)
                            .rotationEffect(
                                .degrees(
                                    HyperliteOpenPRRefreshPulse.rotationDegrees(
                                        isRefreshing: true,
                                        at: context.date
                                    )
                                )
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .transaction { $0.animation = nil }
    }
}

struct HyperliteOpenPRTitleCluster: View {
    let count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("Open PRs")
                .font(HyperliteTypography.heading)
                .foregroundStyle(HyperliteTheme.secondaryText.color)
            if let count {
                Text("\(count)")
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            }
        }
    }
}
