import SwiftUI

private enum HyperliteHoverTiming {
    static let openDelay: Duration = .milliseconds(450)
    static let closeDelay: Duration = .milliseconds(160)
}

private struct HyperliteLeanHoverPopover<PopoverContent: View>: ViewModifier {
    let content: () -> PopoverContent
    @State private var isPresented = false
    @State private var triggerHovered = false
    @State private var popoverHovered = false
    @State private var pendingTask: Task<Void, Never>?

    func body(content trigger: Content) -> some View {
        trigger
            .onHover { hovered in
                triggerHovered = hovered
                hovered ? scheduleOpen() : scheduleClose()
            }
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                content()
                    .padding(10)
                    .frame(width: 300, alignment: .leading)
                    .onHover { hovered in
                        popoverHovered = hovered
                        hovered ? pendingTask?.cancel() : scheduleClose()
                    }
            }
            .onDisappear {
                pendingTask?.cancel()
                pendingTask = nil
            }
    }

    private func scheduleOpen() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: HyperliteHoverTiming.openDelay)
            guard !Task.isCancelled, triggerHovered else { return }
            isPresented = true
        }
    }

    private func scheduleClose() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: HyperliteHoverTiming.closeDelay)
            guard !Task.isCancelled, !triggerHovered, !popoverHovered else { return }
            isPresented = false
        }
    }
}

extension View {
    func hyperliteHoverPopover<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(HyperliteLeanHoverPopover(content: content))
    }
}

struct HyperliteThreadHoverCard: View {
    let thread: HyperliteThread

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(HyperliteInteractionModel.hoverTitle(for: thread))
                .font(HyperliteTypography.semibold(12))
                .lineLimit(2)
            Text(HyperliteInteractionModel.hoverSummary(for: thread))
                .font(HyperliteTypography.regular(11))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
    }
}
