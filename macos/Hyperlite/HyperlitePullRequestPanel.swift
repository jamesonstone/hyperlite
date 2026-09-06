import SwiftUI

struct HyperlitePullRequestPanel: View {
    let scan: HyperliteProjectPullRequestScan
    @ObservedObject var organization: HyperliteDashboardListState
    @ObservedObject var pins: HyperlitePullRequestPinStore
    @State private var draggedRowID: String?

    private var sourceRows: [HyperlitePullRequestRow] {
        HyperlitePullRequestPresentation.rows(scan: scan)
    }

    private var sections: HyperlitePullRequestPinning.Sections {
        pins.sections(for: sourceRows)
    }

    private var availability: [HyperliteProjectPullRequests] {
        HyperlitePullRequestPresentation.availability(scan: scan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if sourceRows.isEmpty && availability.isEmpty {
                Text("No open pull requests")
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .padding(.vertical, 2)
            } else {
                LazyVStack(alignment: .leading, spacing: 3) {
                    sectionLabel("Pinned", count: sections.pinned.count)
                    if sections.pinned.isEmpty {
                        HyperlitePinnedSectionDropTarget(
                            draggedRowID: $draggedRowID,
                            pin: pins.pin
                        )
                    }
                    ForEach(sections.pinned) { row in
                        pullRequestRow(row, pinned: true)
                    }
                    sectionLabel("Open", count: sections.unpinned.count)
                    if sections.unpinned.isEmpty {
                        HyperlitePinnedSectionDropTarget(
                            draggedRowID: $draggedRowID,
                            pin: pins.unpin
                        )
                    }
                    ForEach(sections.unpinned) { row in
                        pullRequestRow(row, pinned: false)
                    }
                    ForEach(availability) { project in
                        HyperlitePullRequestAvailabilityRow(project: project)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open pull requests across configured projects")
        .task(id: scan.generatedAt) {
            organization.reconcilePullRequestReviewMarks(scan: scan)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("Open PRs")
                .font(HyperliteTypography.heading)
                .foregroundStyle(HyperliteTheme.secondaryText.color)
            Text("\(sourceRows.count)")
                .font(HyperliteTypography.compact.monospacedDigit())
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Spacer()
            Text(HyperlitePullRequestPresentation.freshnessLabel(
                observedAt: scan.observedAt
            ))
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
        }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Text("\(count)")
                .font(HyperliteTypography.compact.monospacedDigit())
                .foregroundStyle(HyperliteTheme.mutedText.color)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) pull requests, \(count)")
    }

    private func pullRequestRow(
        _ row: HyperlitePullRequestRow,
        pinned: Bool
    ) -> some View {
        HyperlitePullRequestPanelRow(
            row: row,
            reviewStatus: organization.pullRequestReviewStatus(for: row),
            pinned: pinned,
            draggedRowID: $draggedRowID,
            toggleReview: { organization.togglePullRequestReviewed(row) },
            move: pins.move,
            moveBy: pins.move
        )
    }
}
