import SwiftUI

/// Segmented header bar. Counts share one scale. `oldest` is an age, so it
/// stays a fixed end cap and does not stretch the bar.
enum HyperliteHeaderGraphLayout {
    static let gap: CGFloat = 2
    static let barHeight: CGFloat = 18
    static let minimumSegment: CGFloat = 8
    static let fixedSegment: CGFloat = 52
    static let captionSize: CGFloat = 10

    struct Segment: Equatable, Identifiable {
        let id: String
        let text: String
        let valueText: String
        let help: String
        let weight: Double
        let sharesScale: Bool
        let tone: HyperliteQuickFact.Tone
        let ink: Ink
    }

    enum Ink: Equatable {
        case primary, secondary, muted, red, orange, green, cyan
    }

    enum Caption: Equatable {
        case full, value, none
    }

    static func segments(from facts: [HyperliteQuickFact]) -> [Segment] {
        facts.map { fact in
            let measured = measure(fact)
            return Segment(
                id: fact.id,
                text: fact.text,
                valueText: measured.valueText,
                help: fact.help,
                weight: measured.sharesScale ? Double(measured.magnitude) : 0,
                sharesScale: measured.sharesScale,
                tone: fact.tone,
                ink: ink(id: fact.id, tone: fact.tone)
            )
        }
    }

    static func ink(id: String, tone: HyperliteQuickFact.Tone) -> Ink {
        switch id {
        case "open": .primary
        case "ready": .green
        case "fresh", "running": .cyan
        case "oldest": .muted
        default:
            switch tone {
            case .alert: .red
            case .attention: .orange
            case .neutral: .secondary
            }
        }
    }

    /// Widths sum to `available`, minus the gaps the strip inserts between
    /// segments. A window narrower than the gaps yields empty segments.
    static func widths(segments: [Segment], available: CGFloat) -> [CGFloat] {
        let count = segments.count
        guard count > 0 else { return [] }
        let usable = max(0, available - gap * CGFloat(count - 1))
        if usable == 0 { return Array(repeating: 0, count: count) }

        let flex = segments.indices.filter { segments[$0].sharesScale }
        let caps = segments.indices.filter { !segments[$0].sharesScale }
        if flex.isEmpty { return even(count, usable) }

        let flexFloor = minimumSegment * CGFloat(flex.count)
        if !caps.isEmpty && usable <= flexFloor { return even(count, usable) }

        var capWidth: CGFloat = 0
        if !caps.isEmpty {
            capWidth = min(fixedSegment, (usable - flexFloor) / CGFloat(caps.count))
        }
        let flexBudget = usable - capWidth * CGFloat(caps.count)
        var result = Array(repeating: CGFloat(0), count: count)
        for index in caps { result[index] = capWidth }

        let weights = flex.map { max(segments[$0].weight, 0) }
        let portions = share(weights, budget: flexBudget)
        for (offset, index) in flex.enumerated() {
            result[index] = portions[offset]
        }
        if let lastFlex = flex.last {
            result[lastFlex] += usable - result.reduce(0, +)
        }
        return result
    }

    static func caption(
        width: CGFloat, text: String, valueText: String, fontSize: CGFloat = captionSize
    ) -> Caption {
        if width >= textWidth(text, fontSize: fontSize) + 8 { return .full }
        if width >= textWidth(valueText, fontSize: fontSize) + 6 { return .value }
        return .none
    }

    static func textWidth(_ text: String, fontSize: CGFloat = captionSize) -> CGFloat {
        CGFloat(text.count) * fontSize * 0.62
    }

    private static func measure(_ fact: HyperliteQuickFact) -> (valueText: String, magnitude: Int, sharesScale: Bool) {
        if fact.id == "oldest" {
            let prefix = "oldest "
            let value = fact.text.hasPrefix(prefix) ? String(fact.text.dropFirst(prefix.count)) : fact.text
            let digits = value.prefix { $0.isNumber }
            return (value, Int(String(digits)) ?? 0, false)
        }
        let parts = fact.text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let head = parts.first, let magnitude = Int(head) else {
            return (fact.text, 0, true)
        }
        return (String(head), magnitude, true)
    }

    private static func share(_ weights: [Double], budget: CGFloat) -> [CGFloat] {
        guard !weights.isEmpty else { return [] }
        let total = weights.reduce(0, +)
        if total <= 0 { return even(weights.count, budget) }
        let minimum = min(minimumSegment, budget / CGFloat(weights.count))
        var values = weights.map { budget * CGFloat($0 / total) }
        var locked = Array(repeating: false, count: values.count)
        for _ in values.indices {
            var deficit: CGFloat = 0
            var flexible: CGFloat = 0
            for index in values.indices {
                if values[index] < minimum {
                    deficit += minimum - values[index]
                    values[index] = minimum
                    locked[index] = true
                } else if !locked[index] {
                    flexible += values[index]
                }
            }
            if deficit <= 0 || flexible <= 0 { break }
            let scale = max(0, flexible - deficit) / flexible
            for index in values.indices where !locked[index] {
                values[index] *= scale
            }
        }
        values[values.count - 1] += budget - values.reduce(0, +)
        return values
    }

    private static func even(_ count: Int, _ usable: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        var values = Array(repeating: usable / CGFloat(count), count: count)
        values[count - 1] += usable - values.reduce(0, +)
        return values
    }
}

/// Compact status strip. Widths ease when counts change. Hover reveals a
/// label that does not fit inside its segment.
struct HyperliteHeaderGraph: View {
    let facts: [HyperliteQuickFact]
    @State private var hoveredID: String?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(height: HyperliteHeaderGraphLayout.barHeight)
            .frame(maxWidth: .infinity)
            .overlay { GeometryReader { geometry in bars(width: geometry.size.width) } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pull request summary")
            .onAppear { appeared = true }
    }

    private var motion: Animation? {
        guard appeared, !reduceMotion else { return nil }
        return .easeInOut(duration: 0.5)
    }

    private func bars(width: CGFloat) -> some View {
        let segments = HyperliteHeaderGraphLayout.segments(from: facts)
        let widths = HyperliteHeaderGraphLayout.widths(segments: segments, available: width)
        return HStack(spacing: HyperliteHeaderGraphLayout.gap) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                segmentMark(segment, width: index < widths.count ? widths[index] : 0)
            }
        }
        .frame(width: width, height: HyperliteHeaderGraphLayout.barHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(HyperliteTheme.surface.color.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(HyperliteTheme.mutedText.color.opacity(0.3), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .animation(motion, value: widths)
        .animation(motion, value: segments.map(\.id))
    }

    private func segmentMark(_ segment: HyperliteHeaderGraphLayout.Segment, width: CGFloat) -> some View {
        let caption = HyperliteHeaderGraphLayout.caption(
            width: width,
            text: segment.text,
            valueText: segment.valueText,
            fontSize: HyperliteAppearance.shared.compactSize
        )
        let ink = color(segment.ink)
        let hovered = hoveredID == segment.id
        return ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ink.opacity(hovered ? 0.24 : 0.12))
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(ink)
                    .frame(height: 2)
            }
            if let shown = shown(caption, segment) {
                Text(shown)
                    .font(HyperliteTypography.semibold(HyperliteAppearance.shared.compactSize))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 1)
            }
            if hovered, caption != .full {
                Text(segment.text)
                    .font(HyperliteTypography.semibold(HyperliteAppearance.shared.compactSize))
                    .foregroundStyle(HyperliteTheme.primaryText.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(HyperliteTheme.canvas.color.opacity(0.94), in: Capsule())
                    .overlay(Capsule().strokeBorder(ink, lineWidth: 1))
                    .fixedSize(horizontal: true, vertical: false)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: max(width, 0), height: HyperliteHeaderGraphLayout.barHeight)
        .contentShape(Rectangle())
        .zIndex(hovered ? 1 : 0)
        .help("\(segment.text). \(segment.help)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.text)
        .accessibilityHint(segment.help)
        .onHover { inside in
            if inside {
                hoveredID = segment.id
            } else if hoveredID == segment.id {
                hoveredID = nil
            }
        }
        .transition(.opacity)
    }

    private func shown(
        _ caption: HyperliteHeaderGraphLayout.Caption,
        _ segment: HyperliteHeaderGraphLayout.Segment
    ) -> String? {
        switch caption {
        case .full: segment.text
        case .value: segment.valueText
        case .none: nil
        }
    }

    private func color(_ ink: HyperliteHeaderGraphLayout.Ink) -> Color {
        switch ink {
        case .primary: HyperliteTheme.primaryText.color
        case .secondary: HyperliteTheme.secondaryText.color
        case .muted: HyperliteTheme.mutedText.color
        case .red: HyperliteTheme.red.color
        case .orange: HyperliteTheme.orange.color
        case .green: HyperliteTheme.green.color
        case .cyan: HyperliteTheme.cyan.color
        }
    }
}
