import SwiftUI

struct HyperlitePullRequestRowContent: View {
    static let layout = HyperlitePullRequestRowLayout.titleFirst
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus
    var openIssue: () -> Void = {}
    var openPullRequest: () -> Void = {}

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
                trailingColumns
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

    /// Reserved scan columns: failed pipelines, added, removed, comments, age.
    /// Empty cells keep their width so the same datapoint lines up on every row.
    private var trailingColumns: some View {
        let diff = HyperlitePullRequestPresentation.diffstat(
            additions: row.glance.additions,
            deletions: row.glance.deletions
        )
        let comments = HyperlitePullRequestPresentation.commentsColumn(
            unresolvedThreads: row.unresolvedReviewThreads,
            ciState: row.glance.ciState
        )
        return HStack(alignment: .center, spacing: 6) {
            pipelineColumn
            metric(diff.additionsText, color: HyperliteTheme.green.color)
                .frame(width: HyperlitePullRequestRowLayout.additionsColumnWidth, alignment: .trailing)
            metric(diff.deletionsText, color: HyperliteTheme.red.color)
                .frame(width: HyperlitePullRequestRowLayout.deletionsColumnWidth, alignment: .trailing)
            commentsGlyph(comments)
                .frame(width: HyperlitePullRequestRowLayout.commentsColumnWidth, alignment: .center)
            ageLabel
                .frame(width: HyperlitePullRequestRowLayout.ageColumnWidth, alignment: .trailing)
        }
        .font(HyperliteTypography.compact)
        .monospacedDigit()
        .lineLimit(1)
        .layoutPriority(Self.layout.metadataLayoutPriority)
    }

    private var pipelineColumn: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(row.failedPipelines) { pipeline in
                Label(pipeline.shortName, systemImage: "xmark")
                    .labelStyle(HyperliteCompactLabelStyle())
                    .foregroundStyle(HyperliteTheme.red.color)
            }
        }
        .frame(
            width: HyperlitePullRequestRowLayout.failedPipelineColumnWidth,
            alignment: .trailing
        )
        .clipped()
    }

    private func metric(_ text: String?, color: Color) -> some View {
        Text(text ?? "")
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func commentsGlyph(_ comments: HyperlitePullRequestCommentsColumn) -> some View {
        switch comments {
        case .threads(let count):
            Label("\(count)", systemImage: "text.bubble")
                .labelStyle(HyperliteCompactLabelStyle())
                .foregroundStyle(HyperliteTheme.red.color)
        case .pending:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(HyperliteTheme.cyan.color)
        case .clear:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(HyperliteTheme.green.color)
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
        let comments = HyperlitePullRequestPresentation.commentsColumn(
            unresolvedThreads: row.unresolvedReviewThreads,
            ciState: row.glance.ciState
        ).accessibilityLabel
        return [hover, diff, comments].filter { !$0.isEmpty }.joined(separator: ", ")
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
