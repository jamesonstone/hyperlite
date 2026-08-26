import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HyperlitePullRequestPanelRow: View {
    static let layout = HyperlitePullRequestRowLayout.repositoryFirst
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus
    let toggleReview: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            HyperlitePullRequestReviewToggle(
                row: row,
                status: reviewStatus,
                action: toggleReview
            )
            Button(action: openPullRequest) {
                HyperlitePullRequestRowContent(
                    row: row,
                    reviewStatus: reviewStatus
                )
            }
            .buttonStyle(.plain)
            .disabled(row.url == nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.url?.absoluteString ?? "Pull request URL is unavailable")
            .accessibilityLabel(HyperlitePullRequestRowContent.accessibilityLabel(
                for: row,
                reviewStatus: reviewStatus
            ))
        }
    }

    private func openPullRequest() {
        guard let url = row.url else { return }
        NSWorkspace.shared.open(url)
    }
}

struct HyperlitePullRequestReorderRow: View {
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus
    @Binding var draggedRowID: String?
    let move: (String, String) -> Void
    let moveBy: (String, Int) -> Void

    private var rowAccessibilityLabel: String {
        HyperlitePullRequestRowContent.accessibilityLabel(
            for: row,
            reviewStatus: reviewStatus
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onDrag {
                    draggedRowID = row.id
                    return NSItemProvider(object: row.id as NSString)
                }
            HyperlitePullRequestRowContent(row: row, reviewStatus: reviewStatus)
        }
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.text.identifier],
            delegate: HyperliteReorderDropDelegate(
                targetID: row.id,
                draggedID: $draggedRowID,
                move: move
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reorder \(rowAccessibilityLabel)")
        .accessibilityAction(named: "Move up") { moveBy(row.id, -1) }
        .accessibilityAction(named: "Move down") { moveBy(row.id, 1) }
    }
}

private struct HyperlitePullRequestRowContent: View {
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus

    private var review: HyperliteReviewFeedbackPresentation {
        HyperlitePullRequestPresentation.reviewFeedback(
            unresolvedThreads: row.unresolvedReviewThreads
        )
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(row.repository)
                .frame(width: HyperlitePullRequestPanelRow.layout.repositoryColumnWidth,
                       alignment: .leading)
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(HyperlitePullRequestPanelRow.layout.repositoryLayoutPriority)
            Text("#\(row.number)").frame(width: 42, alignment: .leading)
            Text(row.isDraft ? "draft" : "ready").frame(width: 42, alignment: .leading)
            mergeConflictGlyph
            Text(review.text)
                .frame(width: HyperlitePullRequestPanelRow.layout.reviewFeedbackColumnWidth,
                       alignment: .leading)
                .foregroundStyle(review.needsAttention
                    ? HyperliteTheme.orange.color : HyperliteTheme.mutedText.color)
                .monospacedDigit()
                .help(review.accessibilityLabel)
            Text(row.title)
                .foregroundStyle(row.status == .current
                    ? HyperliteTheme.secondaryText.color : HyperliteTheme.mutedText.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(HyperlitePullRequestPanelRow.layout.titleLayoutPriority)
            Spacer(minLength: 6)
            Text(HyperlitePresentation.ageLabel(for: row.updatedAt))
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .monospacedDigit()
        }
        .font(HyperliteTypography.regular(10))
        .foregroundStyle(HyperliteTheme.secondaryText.color)
        .contentShape(Rectangle())
        .opacity(reviewStatus == .reviewed ? 0.62 : 1)
    }

    @ViewBuilder
    private var mergeConflictGlyph: some View {
        Group {
            if row.hasMergeConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HyperliteTheme.orange.color)
                    .help("Merge conflicts")
            }
        }
        .frame(
            width: HyperlitePullRequestPanelRow.layout.mergeConflictColumnWidth,
            alignment: .leading
        )
        .accessibilityHidden(true)
    }

    static func accessibilityLabel(
        for row: HyperlitePullRequestRow,
        reviewStatus: HyperlitePullRequestReviewStatus
    ) -> String {
        let review = HyperlitePullRequestPresentation.reviewFeedback(
            unresolvedThreads: row.unresolvedReviewThreads
        )
        var parts = [
            "\(row.repository) pull request \(row.number)",
            row.isDraft ? "draft" : "ready",
        ]
        if let conflict = HyperlitePullRequestPresentation.mergeConflictAccessibilityLabel(
            hasMergeConflict: row.hasMergeConflict
        ) {
            parts.append(conflict)
        }
        parts.append(contentsOf: [
            review.accessibilityLabel,
            reviewStatus.accessibilityLabel,
            row.title,
        ])
        return parts.joined(separator: ", ")
    }
}

private struct HyperlitePullRequestReviewToggle: View {
    let row: HyperlitePullRequestRow
    let status: HyperlitePullRequestReviewStatus
    let action: () -> Void

    private var canToggle: Bool {
        status == .reviewed || (
            row.status == .current &&
                !row.headRefOID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private var icon: String {
        switch status {
        case .unreviewed: "square"
        case .reviewed: "checkmark.square.fill"
        case .stale: "exclamationmark.square.fill"
        }
    }

    private var color: Color {
        switch status {
        case .unreviewed: HyperliteTheme.mutedText.color
        case .reviewed: HyperliteTheme.cyan.color
        case .stale: HyperliteTheme.orange.color
        }
    }

    private var help: String {
        switch status {
        case .unreviewed where row.status != .current ||
            row.headRefOID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            "Refresh current GitHub data before marking this pull request reviewed"
        case .unreviewed:
            "Mark reviewed by me for head \(shortHead)"
        case .reviewed:
            "Clear reviewed-by-me mark"
        case .stale:
            "Review mark is stale; mark head \(shortHead) reviewed"
        }
    }

    private var shortHead: String {
        String(row.headRefOID.prefix(7))
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canToggle)
        .help(help)
        .accessibilityLabel("Reviewed by me")
        .accessibilityValue(status.accessibilityLabel)
        .accessibilityHint(help)
    }
}

struct HyperlitePullRequestAvailabilityRow: View {
    static let layout = HyperlitePullRequestRowLayout.repositoryFirst
    let project: HyperliteProjectPullRequests

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(project.repository ?? project.name)
                .frame(width: Self.layout.repositoryColumnWidth, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(Self.layout.repositoryLayoutPriority)
            Text(project.status == .cached ? "cached" : "unavailable")
                .frame(width: Self.layout.availabilityMetadataColumnWidth, alignment: .leading)
            Text(project.message ?? "GitHub data is unavailable")
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(Self.layout.titleLayoutPriority)
            Spacer(minLength: 0)
        }
        .font(HyperliteTypography.regular(10))
        .foregroundStyle(HyperliteTheme.mutedText.color)
        .help(project.message ?? "GitHub data is unavailable")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(project.name), \(project.status.rawValue), " +
            "\(project.message ?? "GitHub data is unavailable")")
    }
}
