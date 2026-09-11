import SwiftUI

enum HyperliteOpenPRRefreshPulse {
    static let interval: TimeInterval = 1.2
    static let dimOpacity: Double = 0.42
    static let glyph = "👻"
    static let accessibilityRefreshing = "Refreshing open pull requests from GitHub"

    static func isBright(at date: Date) -> Bool {
        Int(date.timeIntervalSinceReferenceDate / interval) % 2 == 0
    }

    static func titleOpacity(isRefreshing: Bool, at date: Date) -> Double {
        guard isRefreshing else { return 1 }
        return isBright(at: date) ? 1 : dimOpacity
    }

    static func showsGlyph(_ isRefreshing: Bool) -> Bool {
        isRefreshing
    }
}

struct HyperliteOpenPRRefreshPulseChrome<Content: View>: View {
    let isRefreshing: Bool
    let content: (Double) -> Content

    init(
        isRefreshing: Bool,
        @ViewBuilder content: @escaping (Double) -> Content
    ) {
        self.isRefreshing = isRefreshing
        self.content = content
    }

    var body: some View {
        Group {
            if isRefreshing {
                TimelineView(
                    .periodic(from: .now, by: HyperliteOpenPRRefreshPulse.interval)
                ) { context in
                    content(
                        HyperliteOpenPRRefreshPulse.titleOpacity(
                            isRefreshing: true, at: context.date
                        )
                    )
                }
            } else {
                content(1)
            }
        }
        .transaction { $0.animation = nil }
    }
}

struct HyperliteOpenPRTitleCluster: View {
    let count: Int?
    let isRefreshing: Bool

    var body: some View {
        HyperliteOpenPRRefreshPulseChrome(isRefreshing: isRefreshing) { opacity in
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("Open PRs")
                    .font(HyperliteTypography.heading)
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
                    .opacity(opacity)
                if HyperliteOpenPRRefreshPulse.showsGlyph(isRefreshing) {
                    Text(HyperliteOpenPRRefreshPulse.glyph)
                        .font(HyperliteTypography.compact)
                        .opacity(opacity)
                        .accessibilityHidden(true)
                }
                if let count {
                    Text("\(count)")
                        .font(HyperliteTypography.compact.monospacedDigit())
                        .foregroundStyle(HyperliteTheme.mutedText.color)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(
                HyperliteOpenPRRefreshPulse.showsGlyph(isRefreshing)
                    ? HyperliteOpenPRRefreshPulse.accessibilityRefreshing
                    : ""
            )
        }
    }
}
