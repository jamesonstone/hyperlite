import SwiftUI

struct HyperliteGitHubRateLimitPopover: View {
    let presentation: HyperliteRateLimitPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GITHUB GRAPHQL")
                        .font(HyperliteTypography.semibold(9))
                        .tracking(0.7)
                        .foregroundStyle(HyperliteTheme.mutedText.color)
                    Text("Rate limit")
                        .font(HyperliteTypography.bold(16))
                        .foregroundStyle(HyperliteTheme.primaryText.color)
                }
                Spacer(minLength: 12)
                Text(presentation.statusText)
                    .font(HyperliteTypography.semibold(9))
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(levelColor.opacity(0.14))
                    .clipShape(Capsule())
                    .overlay { Capsule().stroke(levelColor.opacity(0.4), lineWidth: 1) }
            }

            if let usageFraction = presentation.usageFraction {
                HStack(spacing: 8) {
                    metric("USED", presentation.usedDetailText, color: levelColor)
                    metric("LIMIT", presentation.limitDetailText)
                    metric("REMAINING", presentation.remainingDetailText)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(HyperliteTheme.surface.color)
                        Capsule()
                            .fill(levelColor.opacity(0.82))
                            .frame(width: geometry.size.width * min(max(usageFraction, 0), 1))
                    }
                }
                .frame(height: 5)

                VStack(spacing: 0) {
                    detailRow("Resets", presentation.resetText)
                    Rectangle()
                        .fill(HyperliteTheme.elevatedSurface.color.opacity(0.72))
                        .frame(height: 1)
                    detailRow("Observed", presentation.observedText)
                }
                .background(HyperliteTheme.surface.color.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(HyperliteTheme.elevatedSurface.color.opacity(0.8), lineWidth: 1)
                }

                HStack(spacing: 8) {
                    compactDetail("LAST QUERY COST", presentation.costText)
                    compactDetail("NODE COUNT", presentation.nodeCountText)
                }
            } else {
                Text(
                    "No complete observation is available yet. " +
                        "Refresh Hyperlite to request current GitHub data."
                )
                .font(HyperliteTypography.regular(11))
                .foregroundStyle(HyperliteTheme.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HyperliteTheme.surface.color.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            Text("Hover to glance  •  Click to pin")
                .font(HyperliteTypography.regular(9))
                .foregroundStyle(HyperliteTheme.mutedText.color)
        }
        .padding(16)
        .frame(width: 334, alignment: .leading)
        .background(HyperliteTheme.canvas.color)
        .hyperliteTheme()
    }

    private var levelColor: Color {
        switch presentation.level {
        case .unknown: return HyperliteTheme.mutedText.color
        case .healthy: return HyperliteTheme.green.color
        case .warning: return HyperliteTheme.orange.color
        case .critical: return HyperliteTheme.red.color
        }
    }

    private func metric(_ label: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(HyperliteTypography.semibold(8))
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Text(value)
                .font(HyperliteTypography.bold(13).monospacedDigit())
                .foregroundStyle(color ?? HyperliteTheme.primaryText.color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperliteTheme.surface.color.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(HyperliteTheme.elevatedSurface.color.opacity(0.8), lineWidth: 1)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(HyperliteTypography.medium(10))
                .foregroundStyle(HyperliteTheme.secondaryText.color)
            Spacer(minLength: 8)
            Text(value)
                .font(HyperliteTypography.semibold(10).monospacedDigit())
                .foregroundStyle(HyperliteTheme.primaryText.color)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    private func compactDetail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(HyperliteTypography.semibold(8))
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Spacer(minLength: 4)
            Text(value)
                .font(HyperliteTypography.bold(10).monospacedDigit())
                .foregroundStyle(HyperliteTheme.primaryText.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(HyperliteTheme.surface.color.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
