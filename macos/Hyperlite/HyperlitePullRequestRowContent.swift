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

    private var wideRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            pullRequestNumberButton
            issueNumberButton
            pullRequestTarget {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    statusBadge
                    mergeConflictGlyph
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        titleLabel
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        attentionCluster
                        ageLabel
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(Self.layout.titleLayoutPriority)
        }
    }

    // A plain button so a click anywhere but the number opens the pull request,
    // preserving the row's prior single-target behavior.
    private func pullRequestTarget(@ViewBuilder _ content: () -> some View) -> some View {
        Button(action: openPullRequest) {
            content().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.url == nil)
    }

    // Two labeled numbers: the pull request opens the PR, the `GH-<n>` issue
    // opens the tracked issue, so neither number is ambiguous.
    private var pullRequestNumberButton: some View {
        Button(action: openPullRequest) {
            Text(row.pullRequestLabel)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: HyperlitePullRequestRowLayout.pullRequestNumberColumnWidth, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.url == nil)
        .layoutPriority(Self.layout.metadataLayoutPriority)
        .help("Open pull request #\(row.number) on GitHub")
        .accessibilityLabel("Pull request \(row.number)")
    }

    private var issueNumberButton: some View {
        Button(action: openIssue) {
            Text(row.issueLabel ?? "")
                .foregroundStyle(HyperliteTheme.secondaryText.color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: HyperlitePullRequestRowLayout.issueNumberColumnWidth, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.issueURL == nil)
        .layoutPriority(Self.layout.metadataLayoutPriority)
        .help(row.linkedIssueNumber.map { "Open issue #\($0) on GitHub" } ?? "")
        .accessibilityLabel(row.linkedIssueNumber.map { "Issue \($0)" } ?? "")
        .accessibilityHidden(row.issueLabel == nil)
    }

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

    /// Unresolved work, in red beside the age: failed pipelines by short
    /// name, then unresolved review feedback (CodeRabbit or human threads).
    @ViewBuilder
    private var attentionCluster: some View {
        let reviewCount = review.needsAttention ? (row.unresolvedReviewThreads ?? 0) : 0
        if !row.failedPipelines.isEmpty || reviewCount > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ForEach(row.failedPipelines) { pipeline in
                    Label(pipeline.shortName, systemImage: "xmark")
                        .labelStyle(HyperliteCompactLabelStyle())
                        .help("\(pipeline.name) failed")
                }
                if reviewCount > 0 {
                    Label("\(reviewCount)", systemImage: "text.bubble")
                        .labelStyle(HyperliteCompactLabelStyle())
                        .help(review.accessibilityLabel)
                }
            }
            .font(HyperliteTypography.compact)
            .foregroundStyle(HyperliteTheme.red.color)
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
                .frame(
                    width: Self.layout.mergeConflictColumnWidth,
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

/// Icon then text with a tight gap, sized for compact row metadata.
struct HyperliteCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            configuration.icon.font(.system(size: 8, weight: .bold))
            configuration.title
        }
    }
}
