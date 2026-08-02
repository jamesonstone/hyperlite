import Foundation
import SwiftUI

struct HyperliteGitHubRateLimit: Codable, Equatable {
    let limit: Int
    let used: Int
    let remaining: Int
    let resetAt: Date
    let cost: Int
    let nodeCount: Int
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case limit, used, remaining, cost
        case resetAt = "reset_at"
        case nodeCount = "node_count"
        case observedAt = "observed_at"
    }
}

enum HyperliteRateLimitLevel: Equatable {
    case unknown
    case healthy
    case warning
    case critical
}

struct HyperliteRateLimitPresentation: Equatable {
    let usedText: String
    let limitText: String
    let usedDetailText: String
    let limitDetailText: String
    let remainingDetailText: String
    let resetText: String
    let costText: String
    let nodeCountText: String
    let observedText: String
    let statusText: String
    let usageFraction: Double?
    let accessibilityLabel: String
    let level: HyperliteRateLimitLevel

    static func make(
        rateLimit: HyperliteGitHubRateLimit?,
        timeZone: TimeZone = .current
    ) -> HyperliteRateLimitPresentation {
        guard let rateLimit, isComplete(rateLimit) else {
            return HyperliteRateLimitPresentation(
                usedText: "?",
                limitText: "?",
                usedDetailText: "—",
                limitDetailText: "—",
                remainingDetailText: "—",
                resetText: "—",
                costText: "—",
                nodeCountText: "—",
                observedText: "—",
                statusText: "Unavailable",
                usageFraction: nil,
                accessibilityLabel: "GitHub GraphQL rate limit unavailable",
                level: .unknown
            )
        }
        let level = level(remaining: rateLimit.remaining, limit: rateLimit.limit)
        let reset = timestamp(rateLimit.resetAt, timeZone: timeZone)
        let observed = timestamp(rateLimit.observedAt, timeZone: timeZone)
        let used = formatted(rateLimit.used)
        let limit = formatted(rateLimit.limit)
        let remaining = formatted(rateLimit.remaining)
        let cost = formatted(rateLimit.cost)
        let nodes = formatted(rateLimit.nodeCount)
        let status = levelDescription(level)
        return HyperliteRateLimitPresentation(
            usedText: String(rateLimit.used),
            limitText: String(rateLimit.limit),
            usedDetailText: used,
            limitDetailText: limit,
            remainingDetailText: remaining,
            resetText: reset,
            costText: cost,
            nodeCountText: nodes,
            observedText: observed,
            statusText: status,
            usageFraction: Double(rateLimit.used) / Double(rateLimit.limit),
            accessibilityLabel: "GitHub GraphQL rate limit, \(status.lowercased()), " +
                "\(used) of \(limit) calls used, \(remaining) remaining, resets " +
                "\(reset), last query cost \(cost), node count \(nodes), " +
                "observed \(observed)",
            level: level
        )
    }

    private static func isComplete(_ rateLimit: HyperliteGitHubRateLimit) -> Bool {
        rateLimit.limit > 0 && rateLimit.used >= 0 &&
            rateLimit.remaining >= 0 && rateLimit.used <= rateLimit.limit &&
            rateLimit.remaining <= rateLimit.limit &&
            rateLimit.used == rateLimit.limit - rateLimit.remaining &&
            rateLimit.cost >= 0 && rateLimit.nodeCount >= 0
    }

    private static func level(remaining: Int, limit: Int) -> HyperliteRateLimitLevel {
        let percentage = Double(remaining) / Double(limit)
        if percentage <= 0.10 { return .critical }
        if percentage <= 0.20 { return .warning }
        return .healthy
    }

    private static func levelDescription(_ level: HyperliteRateLimitLevel) -> String {
        switch level {
        case .unknown: return "Unavailable"
        case .healthy: return "Healthy capacity"
        case .warning: return "Low capacity warning"
        case .critical: return "Critical capacity"
        }
    }

    private static func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        return formatter.string(from: date)
    }
}

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
