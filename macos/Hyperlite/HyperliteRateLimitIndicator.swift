import SwiftUI

struct HyperliteRateLimitPopoverInteraction: Equatable {
    private(set) var isPresented = false
    private(set) var isPinned = false
    private(set) var triggerHovered = false
    private(set) var popoverHovered = false

    mutating func setTriggerHovered(_ hovered: Bool) {
        triggerHovered = hovered
    }

    mutating func setPopoverHovered(_ hovered: Bool) {
        popoverHovered = hovered
    }

    mutating func openFromHoverIfNeeded() {
        if triggerHovered {
            isPresented = true
        }
    }

    mutating func closeIfIdle() {
        if !triggerHovered, !popoverHovered, !isPinned {
            isPresented = false
        }
    }

    mutating func togglePinned() {
        if isPinned {
            dismiss()
        } else {
            isPinned = true
            isPresented = true
        }
    }

    mutating func dismiss() {
        isPresented = false
        isPinned = false
    }
}

private enum HyperliteRateLimitPopoverTiming {
    static let openDelay: Duration = .milliseconds(350)
    static let closeDelay: Duration = .milliseconds(200)
}

struct HyperliteGitHubRateLimitIndicator: View {
    let rateLimit: HyperliteGitHubRateLimit?
    @State private var interaction = HyperliteRateLimitPopoverInteraction()
    @State private var pendingTask: Task<Void, Never>?

    var body: some View {
        let presentation = HyperliteRateLimitPresentation.make(rateLimit: rateLimit)
        let color = indicatorColor(presentation.level)
        return Button(action: togglePinned) {
            VStack(spacing: 0) {
                quotaText(presentation.usedText, color: color)
                Rectangle()
                    .fill(color.opacity(0.55))
                    .frame(width: 24, height: 1)
                quotaText(presentation.limitText, color: color)
            }
            .frame(width: 38, height: 30)
            .background(
                interaction.isPresented
                    ? HyperliteTheme.elevatedSurface.color.opacity(0.9)
                    : HyperliteTheme.surface.color.opacity(0.72)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        interaction.isPresented
                            ? color.opacity(0.72)
                            : HyperliteTheme.elevatedSurface.color.opacity(0.8),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            interaction.setTriggerHovered(hovered)
            hovered ? scheduleOpen() : scheduleClose()
        }
        .popover(isPresented: presentationBinding, arrowEdge: .top) {
            HyperliteGitHubRateLimitPopover(presentation: presentation)
                .onHover { hovered in
                    interaction.setPopoverHovered(hovered)
                    hovered ? pendingTask?.cancel() : scheduleClose()
                }
        }
        .onDisappear {
            pendingTask?.cancel()
            pendingTask = nil
        }
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint("Show GitHub rate limit details")
    }

    private func quotaText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(HyperliteTypography.bold(8).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 34, height: 13)
    }

    private func indicatorColor(_ level: HyperliteRateLimitLevel) -> Color {
        switch level {
        case .unknown: return HyperliteTheme.mutedText.color
        case .healthy: return HyperliteTheme.secondaryText.color
        case .warning: return HyperliteTheme.orange.color
        case .critical: return HyperliteTheme.red.color
        }
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { interaction.isPresented },
            set: { presented in
                if presented {
                    interaction.openFromHoverIfNeeded()
                } else {
                    interaction.dismiss()
                }
            }
        )
    }

    private func togglePinned() {
        pendingTask?.cancel()
        pendingTask = nil
        interaction.togglePinned()
    }

    private func scheduleOpen() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: HyperliteRateLimitPopoverTiming.openDelay)
            guard !Task.isCancelled else { return }
            interaction.openFromHoverIfNeeded()
        }
    }

    private func scheduleClose() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: HyperliteRateLimitPopoverTiming.closeDelay)
            guard !Task.isCancelled else { return }
            interaction.closeIfIdle()
        }
    }
}
