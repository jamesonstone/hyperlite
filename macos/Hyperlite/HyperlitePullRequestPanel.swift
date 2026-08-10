import SwiftUI

struct HyperlitePullRequestPanel: View {
    let scan: HyperliteProjectPullRequestScan
    @ObservedObject var organization: HyperliteDashboardListState
    @State private var isFilterPresented = false
    @State private var draggedRowID: String?

    private var sourceRows: [HyperlitePullRequestRow] {
        HyperlitePullRequestPresentation.rows(scan: scan)
    }

    private var rows: [HyperlitePullRequestRow] {
        let filter = organization.isReorderingPullRequests
            ? HyperlitePullRequestFilter() : organization.pullRequestFilter
        let sort = organization.isReorderingPullRequests
            ? HyperlitePullRequestSort.custom : organization.pullRequestSort
        return HyperliteDashboardListPresentation.pullRequests(
            sourceRows,
            filter: filter,
            sort: sort,
            customOrder: organization.orderedPullRequestIDs(sourceRows.map(\.id)),
            reviewStatuses: reviewStatuses
        )
    }

    private var reviewStatuses: [String: HyperlitePullRequestReviewStatus] {
        sourceRows.reduce(into: [:]) { values, row in
            values[row.id] = organization.pullRequestReviewStatus(for: row)
        }
    }

    private var availability: [HyperliteProjectPullRequests] {
        let source = HyperlitePullRequestPresentation.availability(scan: scan)
        guard !organization.isReorderingPullRequests else { return source }
        return HyperliteDashboardListPresentation.availability(
            source,
            filter: organization.pullRequestFilter
        )
    }

    private var repositories: [String] {
        Array(Set(sourceRows.map(\.repository))).sorted()
    }

    private var countLabel: String {
        if organization.pullRequestFilter.isActive,
           !organization.isReorderingPullRequests
        {
            return "\(rows.count)/\(sourceRows.count)"
        }
        return "\(sourceRows.count)"
    }

    private var reviewedCount: Int {
        Set(sourceRows.filter {
            organization.pullRequestReviewStatus(for: $0) == .reviewed
        }.map(\.reviewID)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if rows.isEmpty && availability.isEmpty {
                Text(organization.pullRequestFilter.isActive
                    ? "No matching pull requests" : "No open pull requests")
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .padding(.vertical, 2)
            } else {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(rows) { row in
                        if organization.isReorderingPullRequests {
                            HyperlitePullRequestReorderRow(
                                row: row,
                                reviewStatus: organization.pullRequestReviewStatus(for: row),
                                draggedRowID: $draggedRowID,
                                move: organization.movePullRequest,
                                moveBy: organization.movePullRequest
                            )
                        } else {
                            HyperlitePullRequestPanelRow(
                                row: row,
                                reviewStatus: organization.pullRequestReviewStatus(for: row),
                                toggleReview: { organization.togglePullRequestReviewed(row) }
                            )
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
        .task(id: scan.generatedAt) {
            organization.reconcilePullRequestReviewMarks(scan: scan)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("Open PRs")
                .font(HyperliteTypography.semibold(11))
                .foregroundStyle(HyperliteTheme.secondaryText.color)
            Text(countLabel)
                .font(HyperliteTypography.bold(10).monospacedDigit())
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Text("\(reviewedCount) reviewed")
                .font(HyperliteTypography.regular(10).monospacedDigit())
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Spacer()
            if organization.isReorderingPullRequests {
                Text("Reordering all")
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(HyperliteTheme.cyan.color)
                Button("Cancel") {
                    draggedRowID = nil
                    organization.finishPullRequestReordering(commit: false)
                }
                Button("Done") {
                    draggedRowID = nil
                    organization.finishPullRequestReordering(commit: true)
                }
            } else {
                HyperliteDashboardControlButton(
                    systemName: "xmark.square",
                    active: organization.pullRequestReviewMarkCount > 0,
                    label: "Clear all reviewed pull request marks",
                    disabled: organization.pullRequestReviewMarkCount == 0
                ) { organization.clearPullRequestReviewMarks() }
                HyperliteDashboardControlButton(
                    systemName: "line.3.horizontal.decrease",
                    active: organization.pullRequestFilter.isActive,
                    label: "Filter open pull requests"
                ) { isFilterPresented.toggle() }
                .popover(isPresented: $isFilterPresented, arrowEdge: .top) {
                    HyperlitePullRequestFilterPopover(
                        filter: pullRequestFilterBinding,
                        repositories: repositories
                    )
                }
                pullRequestSortMenu
                HyperliteDashboardControlButton(
                    systemName: "line.3.horizontal",
                    active: organization.pullRequestSort == .custom,
                    label: "Reorder open pull requests",
                    disabled: sourceRows.count < 2
                ) {
                    organization.beginPullRequestReordering(currentIDs: sourceRows.map(\.id))
                }
            }
            Text(HyperlitePullRequestPresentation.freshnessLabel(
                observedAt: scan.observedAt
            ))
                .font(HyperliteTypography.regular(10))
                .foregroundStyle(HyperliteTheme.mutedText.color)
        }
    }

    private var pullRequestSortMenu: some View {
        Menu {
            ForEach(HyperlitePullRequestSort.allCases) { sort in
                Button {
                    organization.setPullRequestSort(sort)
                } label: {
                    if organization.pullRequestSort == sort {
                        Label(sort.title, systemImage: "checkmark")
                    } else {
                        Text(sort.title)
                    }
                }
            }
        } label: {
            HyperliteDashboardHeaderIcon(
                systemName: "arrow.up.arrow.down",
                active: organization.pullRequestSort != .recent
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort open pull requests")
        .accessibilityLabel("Sort open pull requests")
    }

    private var pullRequestFilterBinding: Binding<HyperlitePullRequestFilter> {
        Binding(
            get: { organization.pullRequestFilter },
            set: organization.setPullRequestFilter
        )
    }
}
