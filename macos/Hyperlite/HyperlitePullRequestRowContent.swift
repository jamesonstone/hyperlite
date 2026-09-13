import SwiftUI

struct HyperlitePullRequestRowContent: View {
    static let layout = HyperlitePullRequestRowLayout.titleFirst
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus
    let compact: Bool
    var showRepository = true
    var openNumber: () -> Void = {}
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

    private var usesCompactStack: Bool {
        HyperlitePullRequestRowLayout.usesCompactStack(
            compact: compact,
            showRepository: showRepository
        )
    }

    var body: some View {
        Group {
            if usesCompactStack {
                compactStack
            } else {
                wideRow
            }
        }
        .font(HyperliteTypography.body)
        .foregroundStyle(HyperliteTheme.secondaryText.color)
        .opacity(reviewStatus == .reviewed ? 0.62 : 1)
    }

    private var wideRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if showRepository {
                pullRequestTarget { repositoryLabel }
                    .frame(
                        minWidth: 72,
                        idealWidth: 132,
                        maxWidth: Self.layout.repositoryColumnWidth,
                        alignment: .leading
                    )
                    .layoutPriority(Self.layout.repositoryLayoutPriority)
            }
            numberButton
            pullRequestTarget {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    statusBadge
                    mergeConflictGlyph
                    reviewLabel
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        titleLabel
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        ageLabel
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(Self.layout.titleLayoutPriority)
        }
    }

    private var compactStack: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                pullRequestTarget { repositoryLabel }
                    .layoutPriority(-1)
                numberButton
                pullRequestTarget {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        statusBadge
                        mergeConflictGlyph
                        reviewLabel
                    }
                }
            }
            .lineLimit(1)
            pullRequestTarget {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleLabel
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    ageLabel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var repositoryLabel: some View {
        Text(row.repository)
            .font(HyperliteTypography.compact)
            .foregroundStyle(HyperliteTheme.mutedText.color)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // The number opens the tracked issue when the pull request names one, so
    // the ticket is one click away while the title still opens the PR.
    private var numberButton: some View {
        Button(action: openNumber) {
            numberLabel.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.numberURL == nil)
        .help(numberHelp)
        .accessibilityLabel(numberHelp)
    }

    private var numberHelp: String {
        row.numberOpensIssue
            ? "Open issue #\(row.displayNumber)"
            : "Open pull request #\(row.number)"
    }

    private var numberLabel: some View {
        Text("#\(row.displayNumber)")
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(Self.layout.metadataLayoutPriority)
            .frame(minWidth: usesCompactStack ? 0 : 42, alignment: .leading)
            .foregroundStyle(
                row.numberOpensIssue ? HyperliteTheme.secondaryText.color : titleColor
            )
    }

    private var statusBadge: some View {
        Text(row.isDraft ? "draft" : "ready")
            .font(HyperliteTypography.compact)
            .foregroundStyle(
                row.isDraft ? HyperliteTheme.mutedText.color : HyperliteTheme.cyan.color
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(Self.layout.metadataLayoutPriority)
            .frame(minWidth: usesCompactStack ? 0 : 42, alignment: .leading)
    }

    private var reviewLabel: some View {
        Text(review.text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(Self.layout.metadataLayoutPriority)
            .frame(
                minWidth: usesCompactStack
                    ? 0
                    : Self.layout.reviewFeedbackColumnWidth,
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
            .layoutPriority(Self.layout.metadataLayoutPriority)
    }

    @ViewBuilder
    private var mergeConflictGlyph: some View {
        if row.hasMergeConflict {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HyperliteTheme.orange.color)
                .frame(
                    width: usesCompactStack
                        ? nil
                        : Self.layout.mergeConflictColumnWidth,
                    alignment: .leading
                )
                .accessibilityHidden(true)
        } else if !usesCompactStack {
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
