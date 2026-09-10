import SwiftUI

struct HyperlitePullRequestRowContent: View {
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus
    let compact: Bool
    var showRepository = true

    private var review: HyperliteReviewFeedbackPresentation {
        HyperlitePullRequestPresentation.reviewFeedback(
            unresolvedThreads: row.unresolvedReviewThreads
        )
    }

    private var titleColor: Color {
        row.status == .current
            ? HyperliteTheme.primaryText.color
            : HyperliteTheme.mutedText.color
    }

    var body: some View {
        Group {
            if compact && showRepository {
                compactStack
            } else {
                wideRow
            }
        }
        .font(HyperliteTypography.body)
        .foregroundStyle(HyperliteTheme.secondaryText.color)
        .contentShape(Rectangle())
        .opacity(reviewStatus == .reviewed ? 0.62 : 1)
    }

    private var wideRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if showRepository {
                repositoryLabel
                    .frame(
                        minWidth: 72,
                        idealWidth: 132,
                        maxWidth: HyperlitePullRequestRowLayout.titleFirst.repositoryColumnWidth,
                        alignment: .leading
                    )
                    .layoutPriority(HyperlitePullRequestRowLayout.titleFirst.repositoryLayoutPriority)
            }
            numberLabel
            statusBadge
            mergeConflictGlyph
            reviewLabel
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleLabel
                ageLabel
            }
            .layoutPriority(HyperlitePullRequestRowLayout.titleFirst.titleLayoutPriority)
        }
    }

    private var compactStack: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                repositoryLabel
                    .layoutPriority(-1)
                numberLabel
                statusBadge
                mergeConflictGlyph
                reviewLabel
            }
            .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                ageLabel
            }
        }
    }

    private var repositoryLabel: some View {
        Text(row.repository)
            .font(HyperliteTypography.compact)
            .foregroundStyle(HyperliteTheme.mutedText.color)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var numberLabel: some View {
        Text("#\(row.number)")
            .frame(width: compact ? nil : 42, alignment: .leading)
    }

    private var statusBadge: some View {
        Text(row.isDraft ? "draft" : "ready")
            .font(HyperliteTypography.compact)
            .foregroundStyle(
                row.isDraft ? HyperliteTheme.mutedText.color : HyperliteTheme.cyan.color
            )
            .frame(width: compact ? nil : 42, alignment: .leading)
    }

    private var reviewLabel: some View {
        Text(review.text)
            .frame(
                width: compact
                    ? nil
                    : HyperlitePullRequestRowLayout.titleFirst.reviewFeedbackColumnWidth,
                alignment: .leading
            )
            .foregroundStyle(review.needsAttention
                ? HyperliteTheme.orange.color : HyperliteTheme.mutedText.color)
            .monospacedDigit()
    }

    private var titleLabel: some View {
        Text(row.title)
            .foregroundStyle(titleColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var ageLabel: some View {
        Text(HyperlitePresentation.ageLabel(for: row.updatedAt))
            .font(HyperliteTypography.compact)
            .foregroundStyle(HyperliteTheme.mutedText.color)
            .monospacedDigit()
            .fixedSize()
            .layoutPriority(2)
    }

    @ViewBuilder
    private var mergeConflictGlyph: some View {
        if row.hasMergeConflict {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HyperliteTheme.orange.color)
                .frame(
                    width: compact
                        ? nil
                        : HyperlitePullRequestRowLayout.titleFirst.mergeConflictColumnWidth,
                    alignment: .leading
                )
                .accessibilityHidden(true)
        } else if !compact {
            Color.clear
                .frame(
                    width: HyperlitePullRequestRowLayout.titleFirst.mergeConflictColumnWidth,
                    alignment: .leading
                )
                .accessibilityHidden(true)
        }
    }

    static func accessibilityLabel(
        for row: HyperlitePullRequestRow,
        reviewStatus: HyperlitePullRequestReviewStatus
    ) -> String {
        HyperlitePullRequestHoverPresentation.snapshot(
            row: row, reviewStatus: reviewStatus
        ).accessibilityLabel
    }
}
