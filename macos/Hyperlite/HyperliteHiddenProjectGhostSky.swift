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
        GeometryReader { geo in
            ZStack {
                orbitRing(in: geo.size)
                sun(in: geo.size)
                ForEach(0..<HyperliteProjectOrbitPresentation.cometCount, id: \.self) { index in
                    HyperliteOrbitComet(index: index, canvas: geo.size)
                }
                caption
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    HyperliteHiddenProjectOrbitBody(
                        section: section,
                        kind: kinds[section.project.id] ?? .star,
                        origin: HyperliteProjectOrbitPresentation.bodyPoint(
                            index: index, count: sections.count, in: geo.size
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hidden idle projects, \(sections.count)")
    }

    private func orbitRing(in size: CGSize) -> some View {
        let radius = HyperliteProjectOrbitPresentation.radius(in: size)
        return Circle()
            .stroke(HyperliteTheme.mutedText.color.opacity(0.16), lineWidth: 1)
            .frame(width: radius * 2, height: radius * 2)
            .position(HyperliteProjectOrbitPresentation.center(in: size))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func sun(in size: CGSize) -> some View {
        Image(systemName: "sun.max.fill")
            .font(.system(size: HyperliteProjectOrbitPresentation.sunSize))
            .foregroundStyle(HyperliteTheme.orange.color)
            .position(HyperliteProjectOrbitPresentation.center(in: size))
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

struct HyperliteOrbitComet: View {
    let index: Int
    let canvas: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        Text(HyperliteOpenPRRefreshPulse.glyph)
            .font(.system(size: 11))
            .opacity(reduceMotion ? 0.28 : 0.42)
            .position(HyperliteProjectOrbitPresentation.cometHome(index: index, in: canvas))
            .offset(
                drifting && !reduceMotion
                    ? HyperliteProjectOrbitPresentation.cometDrift(index: index)
                    : .zero
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { drifting = true }
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(
                        duration: HyperliteProjectOrbitPresentation.cometDriftDuration(index: index)
                    )
                    .repeatForever(autoreverses: true),
                value: drifting
            )
    }
}

struct HyperliteHiddenProjectOrbitBody: View {
    let section: HyperliteProjectSection
    let kind: HyperliteProjectCelestialKind
    let origin: CGPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var dragging = false
    @State private var offset: CGSize = .zero

    var body: some View {
        VStack(spacing: 2) {
            HyperliteProjectCelestialIcon(kind: kind, diameter: kind.diameter)
                .scaleEffect(hovering || dragging ? 1.18 : 1)
            Text(HyperliteHiddenProjectGhostSkyPresentation.shortName(section.repository))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(
                    hovering || dragging
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
        .offset(offset)
        .position(origin)
        .zIndex(dragging ? 1 : 0)
        .gesture(pull)
        .onHover { hovering = $0 }
        .help(section.project.message ?? section.idleText)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(section.repository), \(section.idleText)")
        .accessibilityHint(section.repositoryURL == nil ? "" : "Opens the repository on GitHub")
        .accessibilityAction(named: "Open repository") { open() }
    }

    private var pull: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance >= HyperliteProjectOrbitPresentation.dragSlop else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragging = true
                    offset = value.translation
                }
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                let clicked = !dragging &&
                    distance < HyperliteProjectOrbitPresentation.dragSlop
                dragging = false
                if reduceMotion {
                    offset = .zero
                } else {
                    withAnimation(
                        .interpolatingSpring(
                            stiffness: HyperliteProjectOrbitPresentation.returnStiffness,
                            damping: HyperliteProjectOrbitPresentation.returnDamping
                        )
                    ) {
                        offset = .zero
                    }
                }
                if clicked { open() }
            }
    }

    private func open() {
        guard let url = section.repositoryURL else { return }
        NSWorkspace.shared.open(url)
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
