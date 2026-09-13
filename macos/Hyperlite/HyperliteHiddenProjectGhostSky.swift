import AppKit
import SwiftUI

enum HyperliteHiddenProjectGhostSkyPresentation {
    static let caption = "watching the quiet ones"
    static let minimumLeftover: CGFloat = 40
    static let tokenSpacing: CGFloat = 10
    static let lineSpacing: CGFloat = 14
    static let minOpacity = 0.42
    static let maxOpacity = 0.70

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
        let hash = seed(id, salt: 17)
        let span = maxOpacity - minOpacity
        return minOpacity + (Double(hash % 29) / 28.0) * span
    }

    static func floatOffset(for id: String) -> CGFloat {
        CGFloat(Int(seed(id, salt: 11) % 9) - 4)
    }

    static func tiltDegrees(for id: String) -> Double {
        Double(Int(seed(id, salt: 23) % 9) - 4)
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

struct HyperliteWrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 12

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(proposal.width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrange(proposal.width, subviews: subviews)
        for (index, frame) in zip(subviews.indices, result.frames) {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(
        _ proposedWidth: CGFloat?,
        subviews: Subviews
    ) -> (size: CGSize, frames: [CGRect]) {
        let width = proposedWidth ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && width.isFinite && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, frames.last?.maxX ?? 0)
        }
        let fittedWidth = width.isFinite ? width : maxX
        return (CGSize(width: fittedWidth, height: y + lineHeight), frames)
    }
}

struct HyperliteHiddenProjectGhostSky: View {
    let sections: [HyperliteProjectSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(HyperliteOpenPRRefreshPulse.glyph)
                    .font(.system(size: 13))
                Text(HyperliteHiddenProjectGhostSkyPresentation.caption)
                    .font(HyperliteTypography.compact)
                Text("\(sections.count)")
                    .font(HyperliteTypography.compact.monospacedDigit())
            }
            .foregroundStyle(HyperliteTheme.mutedText.color)
            .accessibilityHidden(true)
            HyperliteWrappingHStack(
                spacing: HyperliteHiddenProjectGhostSkyPresentation.tokenSpacing,
                lineSpacing: HyperliteHiddenProjectGhostSkyPresentation.lineSpacing
            ) {
                ForEach(sections) { section in
                    HyperliteHiddenProjectGhost(section: section)
                }
            }
        }
        .padding(.top, 12)
        .padding(.leading, HyperlitePullRequestRowLayout.rowChromeLeading)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hidden idle projects, \(sections.count)")
    }
}

struct HyperliteHiddenProjectGhost: View {
    let section: HyperliteProjectSection

    var body: some View {
        Button {
            guard let url = section.repositoryURL else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Text(HyperliteOpenPRRefreshPulse.glyph)
                    .font(.system(size: 12))
                Text(HyperliteHiddenProjectGhostSkyPresentation.shortName(section.repository))
                    .font(HyperliteTypography.compact)
                    .lineLimit(1)
            }
            .foregroundStyle(HyperliteTheme.mutedText.color)
            .opacity(HyperliteHiddenProjectGhostSkyPresentation.opacity(for: section.id))
            .offset(y: HyperliteHiddenProjectGhostSkyPresentation.floatOffset(for: section.id))
            .rotationEffect(
                .degrees(HyperliteHiddenProjectGhostSkyPresentation.tiltDegrees(for: section.id))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(section.repositoryURL == nil)
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
