import Foundation
import SwiftUI

struct HyperlitePullRequestGlance: Equatable {
    var authorLogin = ""
    var headRefName = ""
    var baseRefName = ""
    var labels: [String] = []
    var assignees: [String] = []
    var reviewRequests: [String] = []
    var reviewDecision = ""
    var additions = 0
    var deletions = 0
    var changedFiles = 0
    var commentCount = 0
    var ciState = ""

    static let empty = HyperlitePullRequestGlance()
}

enum HyperlitePullRequestHoverPresentation {
    static func lines(
        row: HyperlitePullRequestRow,
        reviewStatus: HyperlitePullRequestReviewStatus
    ) -> [String] {
        let glance = row.glance
        let review = HyperlitePullRequestPresentation.reviewFeedback(
            unresolvedThreads: row.unresolvedReviewThreads
        )
        var lines = [
            "\(row.repository) #\(row.number)",
            row.title,
            row.isDraft ? "draft" : "ready",
        ]
        if !glance.headRefName.isEmpty {
            let base = glance.baseRefName.isEmpty ? "base" : glance.baseRefName
            lines.append("\(glance.headRefName) → \(base)")
        }
        if !glance.authorLogin.isEmpty { lines.append("author \(glance.authorLogin)") }
        if !glance.labels.isEmpty { lines.append("labels \(glance.labels.joined(separator: ", "))") }
        if !glance.assignees.isEmpty {
            lines.append("assignees \(glance.assignees.joined(separator: ", "))")
        }
        if glance.changedFiles > 0 || glance.additions > 0 || glance.deletions > 0 {
            lines.append("+\(glance.additions) / -\(glance.deletions) · \(glance.changedFiles) files")
        }
        if row.hasMergeConflict { lines.append("merge conflicts") }
        lines.append(review.accessibilityLabel)
        if !glance.reviewDecision.isEmpty {
            lines.append("review \(readableDecision(glance.reviewDecision))")
        }
        if !glance.reviewRequests.isEmpty {
            lines.append("requested \(glance.reviewRequests.joined(separator: ", "))")
        }
        if glance.commentCount > 0 { lines.append("\(glance.commentCount) comments") }
        if !glance.ciState.isEmpty { lines.append("CI \(glance.ciState.lowercased())") }
        lines.append(reviewStatus.accessibilityLabel)
        lines.append(HyperlitePresentation.ageLabel(for: row.updatedAt))
        if !row.headRefOID.isEmpty { lines.append(String(row.headRefOID.prefix(7))) }
        if let url = row.url { lines.append(url.absoluteString) }
        return lines
    }

    private static func readableDecision(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").lowercased()
    }
}

struct HyperlitePullRequestHoverCard: View {
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus

    var body: some View {
        let lines = HyperlitePullRequestHoverPresentation.lines(
            row: row, reviewStatus: reviewStatus
        )
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index < 2 ? HyperliteTypography.heading : HyperliteTypography.compact)
                    .foregroundStyle(
                        index < 2
                            ? HyperliteTheme.primaryText.color
                            : HyperliteTheme.secondaryText.color
                    )
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: 360, alignment: .leading)
        .background(HyperliteTheme.canvas.color)
        .hyperliteTheme()
    }
}

