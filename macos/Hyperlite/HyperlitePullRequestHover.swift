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
    var summary = ""

    static let empty = HyperlitePullRequestGlance()
}

struct HyperlitePullRequestHoverSnapshot: Equatable {
    var identity = ""
    var title = ""
    var meta = ""
    var summary = ""
    var nextStep = ""
    var nextStepNeedsAttention = false
    var status = ""

    var accessibilityLabel: String {
        [identity, title, meta, summary, nextStep, status]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

enum HyperlitePullRequestHoverPresentation {
    static func snapshot(
        row: HyperlitePullRequestRow,
        reviewStatus: HyperlitePullRequestReviewStatus
    ) -> HyperlitePullRequestHoverSnapshot {
        let glance = row.glance
        let next = nextStep(row: row, glance: glance, reviewStatus: reviewStatus)
        var card = HyperlitePullRequestHoverSnapshot(
            identity: "\(row.repository) #\(row.number)",
            title: row.title,
            meta: "\(row.isDraft ? "draft" : "ready") · \(HyperlitePresentation.ageLabel(for: row.updatedAt))",
            summary: glance.summary,
            nextStep: next.text,
            nextStepNeedsAttention: next.needsAttention
        )
        if shouldShowCI(glance.ciState, nextStep: next.text) {
            card.status = "CI \(glance.ciState.lowercased())"
        }
        return card
    }

    private static func nextStep(
        row: HyperlitePullRequestRow,
        glance: HyperlitePullRequestGlance,
        reviewStatus: HyperlitePullRequestReviewStatus
    ) -> (text: String, needsAttention: Bool) {
        let ci = glance.ciState.uppercased()
        if row.hasMergeConflict { return ("fix merge conflicts", true) }
        if ci == "FAILURE" || ci == "ERROR" { return ("CI failing", true) }
        if let threads = row.unresolvedReviewThreads, threads > 0 {
            let noun = threads == 1 ? "thread" : "threads"
            return ("\(threads) unresolved review \(noun)", true)
        }
        if reviewStatus == .stale { return ("review the new head", true) }
        if row.isDraft { return ("still a draft", false) }
        if glance.reviewDecision.uppercased() == "CHANGES_REQUESTED" {
            return ("changes requested", true)
        }
        if ci == "PENDING" || ci == "EXPECTED" { return ("CI pending", false) }
        if !glance.reviewRequests.isEmpty {
            return ("waiting on \(glance.reviewRequests.joined(separator: ", "))", false)
        }
        if glance.reviewDecision.uppercased() == "REVIEW_REQUIRED" {
            return ("waiting on review", false)
        }
        if glance.reviewDecision.uppercased() == "APPROVED" {
            return ("ready to merge", false)
        }
        return ("no blockers", false)
    }

    private static func shouldShowCI(_ ciState: String, nextStep: String) -> Bool {
        if ciState.isEmpty { return false }
        let step = nextStep.lowercased()
        return !step.hasPrefix("ci ") && step != "ready to merge"
    }
}

struct HyperlitePullRequestHoverCard: View {
    let row: HyperlitePullRequestRow
    let reviewStatus: HyperlitePullRequestReviewStatus

    var body: some View {
        let card = HyperlitePullRequestHoverPresentation.snapshot(
            row: row, reviewStatus: reviewStatus
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(card.identity)
                    .font(HyperliteTypography.heading)
                    .foregroundStyle(HyperliteTheme.primaryText.color)
                Spacer(minLength: 8)
                Text(card.meta)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
            }
            Text(card.title)
                .font(HyperliteTypography.heading)
                .foregroundStyle(HyperliteTheme.primaryText.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !card.summary.isEmpty {
                Text(card.summary)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(card.nextStep)
                .font(HyperliteTypography.compact)
                .foregroundStyle(
                    card.nextStepNeedsAttention
                        ? HyperliteTheme.orange.color
                        : HyperliteTheme.primaryText.color
                )
            if !card.status.isEmpty {
                Text(card.status)
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
            }
        }
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(HyperliteTheme.canvas.color)
        .hyperliteTheme()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.accessibilityLabel)
    }
}
