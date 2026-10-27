import SwiftUI

struct HyperlitePullRequestRowContent: View {
    static let layout = HyperlitePullRequestRowLayout.titleFirst
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus
    var openIssue: () -> Void = {}
    var openPullRequest: () -> Void = {}

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
        wideRow
        .font(HyperliteTypography.body)
        .foregroundStyle(HyperliteTheme.secondaryText.color)
        .opacity(reviewStatus == .reviewed ? 0.62 : 1)
    }

    /// One button opens the pull request from anywhere on the row; the
    /// `GH-<n>` issue number is a separate button laid over its column. Fewer
    /// interactive regions per row keeps scrolling cheap, because SwiftUI
    /// hit-tests every visible region on each scroll frame.
    private var wideRow: some View {
        Button(action: openPullRequest) {
            HStack(alignment: .center, spacing: Self.columnSpacing) {
                Text(row.pullRequestLabel)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .frame(width: HyperlitePullRequestRowLayout.pullRequestNumberColumnWidth, alignment: .leading)
                Color.clear
                    .frame(width: HyperlitePullRequestRowLayout.issueNumberColumnWidth, height: 1)
                statusBadge
                mergeConflictGlyph
                titleLabel
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(Self.layout.titleLayoutPriority)
                trailingCluster
                ageLabel
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.url == nil)
        .overlay(alignment: .leading) {
            if let issueLabel = row.issueLabel {
                Button(action: openIssue) {
                    Text(issueLabel)
                        .foregroundStyle(HyperliteTheme.secondaryText.color)
                        .lineLimit(1)
                        .frame(width: HyperlitePullRequestRowLayout.issueNumberColumnWidth, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: HyperlitePullRequestRowLayout.pullRequestNumberColumnWidth + Self.columnSpacing)
                .accessibilityLabel("Issue \(issueLabel)")
            }
        }
    }

    private static let columnSpacing: CGFloat = 7

    private var statusBadge: some View {
        Text(row.isDraft ? "draft" : "ready")
            .font(
                row.isDraft
                    ? HyperliteTypography.compact
                    : HyperliteTypography.semibold(HyperliteAppearance.shared.compactSize)
            )
            .foregroundStyle(
                row.isDraft ? HyperliteTheme.mutedText.color : HyperliteTheme.cyan.color
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(Self.layout.metadataLayoutPriority)
            .frame(minWidth: 42, alignment: .leading)
    }

    /// Failed pipelines, then added/removed counts, then unresolved review
    /// feedback, then the age. Diffstat is informational; unresolved work
    /// stays red.
    @ViewBuilder
    private var trailingCluster: some View {
        let reviewCount = review.needsAttention ? (row.unresolvedReviewThreads ?? 0) : 0
        let diff = HyperlitePullRequestPresentation.diffstat(
            additions: row.glance.additions,
            deletions: row.glance.deletions
        )
        if !row.failedPipelines.isEmpty || diff.visible || reviewCount > 0 {
            HStack(alignment: .center, spacing: 6) {
                ForEach(row.failedPipelines) { pipeline in
                    Label(pipeline.shortName, systemImage: "xmark")
                        .labelStyle(HyperliteCompactLabelStyle())
                        .foregroundStyle(HyperliteTheme.red.color)
                }
                if diff.visible {
                    HStack(alignment: .center, spacing: 4) {
                        if let added = diff.additionsText {
                            Text(added).foregroundStyle(HyperliteTheme.green.color)
                        }
                        if let removed = diff.deletionsText {
                            Text(removed).foregroundStyle(HyperliteTheme.red.color)
                        }
                    }
                }
                if reviewCount > 0 {
                    Label("\(reviewCount)", systemImage: "text.bubble")
                        .labelStyle(HyperliteCompactLabelStyle())
                        .foregroundStyle(HyperliteTheme.red.color)
                }
            }
            .font(HyperliteTypography.compact)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .layoutPriority(Self.layout.metadataLayoutPriority)
        }
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
            .layoutPriority(Self.layout.metadataLayoutPriority)
    }

    @ViewBuilder
    private var mergeConflictGlyph: some View {
        if row.hasMergeConflict {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HyperliteTheme.orange.color)
                .frame(
                    width: Self.layout.mergeConflictColumnWidth,
                    alignment: .leading
                )
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: Self.layout.mergeConflictColumnWidth, height: 1)
                .accessibilityHidden(true)
        }
    }

    static func accessibilityLabel(
        for row: HyperlitePullRequestRow,
        reviewStatus: HyperlitePullRequestReviewStatus
    ) -> String {
        let hover = HyperlitePullRequestHoverPresentation.snapshot(
            row: row, reviewStatus: reviewStatus
        ).accessibilityLabel
        let diff = HyperlitePullRequestPresentation.diffstat(
            additions: row.glance.additions,
            deletions: row.glance.deletions
        ).accessibilityLabel
        return diff.isEmpty ? hover : hover + ", " + diff
    }
}

/// Icon then text with a tight gap, sized for compact row metadata.
struct HyperliteCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 2) {
            configuration.icon.font(.system(size: 8, weight: .bold))
            configuration.title
        }
    }
}
