import AppKit
import SwiftUI

enum HyperliteHiddenProjectGhostSkyPresentation {
    static let caption = "watching the quiet ones"
    static let minimumLeftover: CGFloat = 40

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
}

struct HyperliteMeasuredHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HyperliteHiddenProjectGhostSky: View {
    let sections: [HyperliteProjectSection]
    let kinds: [String: HyperliteProjectCelestialKind]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                field(phase: 0, date: Date(timeIntervalSinceReferenceDate: 0))
            } else {
                TimelineView(
                    .periodic(from: .now, by: HyperliteProjectOrbitPresentation.tickInterval)
                ) { context in
                    field(
                        phase: HyperliteProjectOrbitPresentation.phase(
                            at: context.date, reduceMotion: false
                        ),
                        date: context.date
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hidden idle projects, \(sections.count)")
    }

    private func field(phase: Double, date: Date) -> some View {
        GeometryReader { geo in
            ZStack {
                sun(in: geo.size)
                ForEach(0..<HyperliteProjectOrbitPresentation.cometCount, id: \.self) { index in
                    comet(index: index, at: date, in: geo.size)
                }
                caption
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    HyperliteHiddenProjectOrbitBody(
                        section: section,
                        kind: kinds[section.project.id] ?? .star,
                        origin: HyperliteProjectOrbitPresentation.bodyPoint(
                            index: index,
                            count: sections.count,
                            in: geo.size,
                            phase: phase
                        )
                    )
                }
            }
        }
    }

    private func sun(in size: CGSize) -> some View {
        let origin = HyperliteProjectOrbitPresentation.center(in: size)
        return Image(systemName: "sun.max.fill")
            .font(.system(size: HyperliteProjectOrbitPresentation.sunSize))
            .foregroundStyle(HyperliteTheme.orange.color)
            .position(origin)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func comet(index: Int, at date: Date, in size: CGSize) -> some View {
        Text(HyperliteOpenPRRefreshPulse.glyph)
            .font(.system(size: 11))
            .opacity(reduceMotion ? 0.28 : 0.42)
            .position(
                HyperliteProjectOrbitPresentation.cometPoint(
                    index: index, at: date, in: size, reduceMotion: reduceMotion
                )
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HyperliteHiddenProjectOrbitBody: View {
    let section: HyperliteProjectSection
    let kind: HyperliteProjectCelestialKind
    let origin: CGPoint
    @State private var hovering = false

    var body: some View {
        Button {
            guard let url = section.repositoryURL else { return }
            NSWorkspace.shared.open(url)
        } label: {
            VStack(spacing: 2) {
                HyperliteProjectCelestialIcon(kind: kind, diameter: kind.diameter)
                    .scaleEffect(hovering ? 1.18 : 1)
                Text(HyperliteHiddenProjectGhostSkyPresentation.shortName(section.repository))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(
                        hovering
                            ? HyperliteTheme.primaryText.color
                            : HyperliteTheme.secondaryText.color
                    )
                    .lineLimit(1)
                    .frame(maxWidth: HyperliteProjectOrbitPresentation.labelWidth)
            }
            .frame(
                width: max(HyperliteProjectOrbitPresentation.hitSize, 64),
                height: max(HyperliteProjectOrbitPresentation.hitSize, 44)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(section.repositoryURL == nil)
        .position(origin)
        .onHover { hovering = $0 }
        .help(section.project.message ?? section.idleText)
        .accessibilityLabel("\(section.repository), \(section.idleText)")
        .accessibilityHint(section.repositoryURL == nil ? "" : "Opens the repository on GitHub")
    }
}

struct HyperliteOpenPRWatchColumn<Content: View>: View {
    let compact: Bool
    let hideIdle: Bool
    let hiddenSections: [HyperliteProjectSection]
    var celestialKinds: [String: HyperliteProjectCelestialKind] = [:]
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
                    HyperliteHiddenProjectGhostSky(
                        sections: hiddenSections,
                        kinds: celestialKinds
                    )
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
