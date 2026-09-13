import SwiftUI

struct HyperliteWorkflowStrip: View {
    let chips: [HyperliteWorkflowChip]
    let compact: Bool
    var expands = false

    var body: some View {
        let shown = compact
            ? HyperliteWorkflowStripPresentation.compactChips(chips)
            : (visible: chips, hiddenCount: 0)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(shown.visible) { chip in
                HyperliteWorkflowChipView(chip: chip)
            }
            if shown.hiddenCount > 0 {
                Text("+\(shown.hiddenCount)")
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            }
        }
        .frame(maxWidth: expands ? .infinity : nil, alignment: .leading)
    }
}

struct HyperliteWorkflowChipView: View {
    let chip: HyperliteWorkflowChip
    @State private var hoverPresented = false
    @State private var chipHovered = false
    @State private var cardHovered = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Group {
            if case .running(let since) = chip.state {
                HyperliteRunningWorkflowChip(title: chip.title, since: since)
            } else {
                HStack(spacing: 3) {
                    if let dot = dotColor {
                        Circle().fill(dot).frame(width: 5, height: 5)
                    }
                    Text(label)
                        .font(HyperliteTypography.compact)
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
        .onHover { updateHover(chip: $0) }
        .popover(isPresented: $hoverPresented, arrowEdge: .bottom) {
            HyperliteWorkflowHoverCard(chip: chip) { updateHover(card: $0) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibilityLabel(now: Date()))
    }

    private var label: String {
        if case .staleRunning(let lastSeen) = chip.state {
            return "\(chip.title) · \(HyperliteWorkflowStripPresentation.lastSeenLabel(lastSeen))"
        }
        return chip.title
    }

    private var dotColor: Color? {
        switch chip.state {
        case .success: HyperliteTheme.green.color
        case .failure: HyperliteTheme.red.color
        case .staleRunning: HyperliteTheme.orange.color
        case .cancelled, .neutral: HyperliteTheme.mutedText.color
        case .idle, .running: nil
        }
    }

    private var textColor: Color {
        switch chip.state {
        case .idle: HyperliteTheme.mutedText.color
        case .failure: HyperliteTheme.orange.color
        default: HyperliteTheme.secondaryText.color
        }
    }

    // The hover card carries the run and deployment-log buttons, so it must
    // stay open while the pointer is inside it, not only over the chip.
    private func updateHover(chip: Bool? = nil, card: Bool? = nil) {
        if let chip { chipHovered = chip }
        if let card { cardHovered = card }
        let shouldShow = HyperliteWorkflowHoverPresentation.shouldPresent(
            chipHovered: chipHovered, cardHovered: cardHovered
        )
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            let delay: Duration = shouldShow ? .milliseconds(350) : .milliseconds(200)
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hoverPresented = shouldShow
        }
    }
}
