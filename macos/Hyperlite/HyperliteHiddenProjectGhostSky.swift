import AppKit
import SwiftUI

enum HyperliteHiddenProjectGhostSkyPresentation {
    static let caption = "watching the quiet ones"
    static let minimumLeftover: CGFloat = 40
    static let minOpacity = 0.28
    static let maxOpacity = 0.78
    static let inset: CGFloat = 22
    static let goldenAngle = 2.399963229728653

    static func showsSky(
        compact: Bool,
        hideIdle: Bool,
        hiddenCount: Int,
        leftover: CGFloat
    ) -> Bool {
        compact && hideIdle && hiddenCount > 0 && leftover >= minimumLeftover
    }

    static func shortName(_ repository: String) -> String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }

    static func opacity(for id: String) -> Double {
        let span = maxOpacity - minOpacity
        return minOpacity + (Double(seed(id, salt: 17) % 29) / 28.0) * span
    }

    static func glyphSize(for id: String) -> CGFloat {
        14 + CGFloat(seed(id, salt: 5) % 11)
    }

    static func drift(for id: String) -> CGSize {
        CGSize(
            width: CGFloat(Int(seed(id, salt: 13) % 9) - 4),
            height: CGFloat(Int(seed(id, salt: 19) % 11) - 5)
        )
    }

    static func driftDuration(for id: String) -> Double {
        3.1 + Double(seed(id, salt: 29) % 21) / 10.0
    }

    static func point(
        for id: String,
        index: Int,
        count: Int,
        in size: CGSize
    ) -> CGPoint {
        let usable = CGSize(
            width: max(size.width - inset * 2, 1),
            height: max(size.height - inset * 2, 1)
        )
        let total = max(count, 1)
        let radius = sqrt(Double(index + 1) / Double(total)) * min(usable.width, usable.height) * 0.46
        let angle = goldenAngle * Double(index)
        let jitterX = CGFloat(Int(seed(id, salt: 3) % 15) - 7)
        let jitterY = CGFloat(Int(seed(id, salt: 7) % 13) - 6)
        let x = inset + usable.width * 0.52 + CGFloat(cos(angle)) * radius + jitterX
        let y = inset + usable.height * 0.46 + CGFloat(sin(angle)) * radius + jitterY
        return CGPoint(
            x: min(max(x, inset), size.width - inset),
            y: min(max(y, inset), size.height - inset)
        )
    }

    private static func seed(_ id: String, salt: Int) -> UInt64 {
        id.unicodeScalars.reduce(UInt64(salt)) { partial, scalar in
            partial &* 33 &+ UInt64(scalar.value)
        }
    }
}

struct HyperliteMeasuredHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HyperliteHiddenProjectGhostSky: View {
    let sections: [HyperliteProjectSection]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Text(HyperliteOpenPRRefreshPulse.glyph)
                    .font(.system(size: min(geo.size.width, geo.size.height) * 0.42))
                    .opacity(0.06)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                caption
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    HyperliteHiddenProjectGhost(
                        section: section,
                        origin: HyperliteHiddenProjectGhostSkyPresentation.point(
                            for: section.id,
                            index: index,
                            count: sections.count,
                            in: geo.size
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hidden idle projects, \(sections.count)")
    }

    private var caption: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(HyperliteOpenPRRefreshPulse.glyph)
                .font(.system(size: 13))
            Text(HyperliteHiddenProjectGhostSkyPresentation.caption)
                .font(HyperliteTypography.compact)
            Text("\(sections.count)")
                .font(HyperliteTypography.compact.monospacedDigit())
        }
        .foregroundStyle(HyperliteTheme.mutedText.color)
        .padding(.leading, 18)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }
}

struct HyperliteHiddenProjectGhost: View {
    let section: HyperliteProjectSection
    let origin: CGPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false
    @State private var hovering = false

    var body: some View {
        Button {
            guard let url = section.repositoryURL else { return }
            NSWorkspace.shared.open(url)
        } label: {
            VStack(spacing: 2) {
                Text(HyperliteOpenPRRefreshPulse.glyph)
                    .font(.system(size: HyperliteHiddenProjectGhostSkyPresentation.glyphSize(for: section.id)))
                if hovering {
                    Text(HyperliteHiddenProjectGhostSkyPresentation.shortName(section.repository))
                        .font(HyperliteTypography.compact)
                        .foregroundStyle(HyperliteTheme.secondaryText.color)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(HyperliteTheme.mutedText.color)
            .opacity(hovering ? 1 : HyperliteHiddenProjectGhostSkyPresentation.opacity(for: section.id))
            .scaleEffect(hovering ? 1.28 : 1)
            .offset(drifting && !reduceMotion
                ? HyperliteHiddenProjectGhostSkyPresentation.drift(for: section.id)
                : .zero)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(section.repositoryURL == nil)
        .position(origin)
        .onHover { hovering = $0 }
        .onAppear { drifting = true }
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(
                    duration: HyperliteHiddenProjectGhostSkyPresentation.driftDuration(for: section.id)
                )
                .repeatForever(autoreverses: true),
            value: drifting
        )
        .help(section.project.message ?? section.idleText)
        .accessibilityLabel("\(section.repository), \(section.idleText)")
        .accessibilityHint(section.repositoryURL == nil ? "" : "Opens the repository on GitHub")
    }
}

struct HyperliteOpenPRWatchColumn<Content: View>: View {
    let compact: Bool
    let hideIdle: Bool
    let hiddenSections: [HyperliteProjectSection]
    let isRefreshing: Bool
    @ViewBuilder var content: Content
    @State private var listHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let leftover = listHeight > 0 ? max(geo.size.height - listHeight, 0) : 0
            let showSky = HyperliteHiddenProjectGhostSkyPresentation.showsSky(
                compact: compact,
                hideIdle: hideIdle,
                hiddenCount: hiddenSections.count,
                leftover: leftover
            )
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.vertical, showsIndicators: true) {
                    content
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: HyperliteMeasuredHeightKey.self,
                                    value: proxy.size.height
                                )
                            }
                        }
                }
                .onPreferenceChange(HyperliteMeasuredHeightKey.self) { listHeight = $0 }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: showSky ? listHeight : .infinity,
                    alignment: .topLeading
                )
                if showSky {
                    HyperliteHiddenProjectGhostSky(sections: hiddenSections)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .overlay {
            HyperliteOpenPRRefreshGhostOverlay(isRefreshing: isRefreshing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
