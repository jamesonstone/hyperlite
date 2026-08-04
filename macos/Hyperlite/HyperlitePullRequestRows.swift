import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HyperlitePullRequestPanelRow: View {
    static let layout = HyperlitePullRequestRowLayout.repositoryFirst
    let row: HyperlitePullRequestRow

    var body: some View {
        Button(action: openPullRequest) {
            HyperlitePullRequestRowContent(row: row)
        }
        .buttonStyle(.plain)
        .disabled(row.url == nil)
        .help(row.url?.absoluteString ?? "Pull request URL is unavailable")
        .accessibilityLabel(HyperlitePullRequestRowContent.accessibilityLabel(for: row))
    }

    private func openPullRequest() {
        guard let url = row.url else { return }
        NSWorkspace.shared.open(url)
    }
}

struct HyperlitePullRequestReorderRow: View {
    let row: HyperlitePullRequestRow
    @Binding var draggedRowID: String?
    let move: (String, String) -> Void
    let moveBy: (String, Int) -> Void

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
            HyperlitePullRequestRowContent(row: row)
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
        .accessibilityLabel("Reorder \(HyperlitePullRequestRowContent.accessibilityLabel(for: row))")
        .accessibilityAction(named: "Move up") { moveBy(row.id, -1) }
        .accessibilityAction(named: "Move down") { moveBy(row.id, 1) }
    }
}

private struct HyperlitePullRequestRowContent: View {
    let row: HyperlitePullRequestRow

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
    }

    static func accessibilityLabel(for row: HyperlitePullRequestRow) -> String {
        let review = HyperlitePullRequestPresentation.reviewFeedback(
            unresolvedThreads: row.unresolvedReviewThreads
        )
        return "\(row.repository) pull request \(row.number), " +
            "\(row.isDraft ? "draft" : "ready"), \(review.accessibilityLabel), \(row.title)"
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
