import SwiftUI

struct HyperlitePullRequestPanel: View {
    let scan: HyperliteProjectPullRequestScan
    @ObservedObject var organization: HyperliteDashboardListState
    @ObservedObject var pins: HyperlitePullRequestPinStore
    var compactRows = false
    var isRefreshing = false
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
                    if sections.unpinned.isEmpty {
                        sectionLabel("Open", count: 0)
                        HyperlitePinnedSectionDropTarget(
                            draggedRowID: $draggedRowID,
                            pin: pins.unpin
                        )
                    }
                    ForEach(sections.unpinnedGroups) { group in
                        HyperliteProjectSectionHeader(
                            repository: group.repository,
                            count: group.rows.count,
                            draggedRowID: $draggedRowID,
                            drop: { pins.move($0, over: group.rows[0].id, rows: sourceRows) }
                        )
                        ForEach(group.rows) { row in
                            pullRequestRow(row, pinned: false)
                        }
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
        .accessibilityValue(
            isRefreshing ? HyperliteOpenPRRefreshPulse.accessibilityRefreshing : ""
        )
        .task(id: scan.generatedAt) {
            organization.reconcilePullRequestReviewMarks(scan: scan)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            HyperliteOpenPRTitleCluster(
                count: sourceRows.count,
                isRefreshing: isRefreshing
            )
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
            compact: compactRows,
            showRepository: pinned,
            draggedRowID: $draggedRowID,
            toggleReview: { organization.togglePullRequestReviewed(row) },
            move: { pins.move($0, over: $1, rows: sourceRows) },
            moveBy: { pins.move($0, by: $1, rows: sourceRows) }
        )
    }
}
