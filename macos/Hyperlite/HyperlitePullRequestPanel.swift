import SwiftUI

struct HyperlitePullRequestPanel: View {
    let scan: HyperliteProjectPullRequestScan
    @ObservedObject var organization: HyperliteDashboardListState
    @ObservedObject var pins: HyperlitePullRequestPinStore
    var compactRows = false
    var isRefreshing = false
    var isPollingActivity = false
    @State private var draggedRowID: String?
    @State private var chipClock = Date()
    @AppStorage("hyperlite.dashboard.open-pr-hide-idle") private var hideIdleProjects = true

    private var sourceRows: [HyperlitePullRequestRow] {
        HyperlitePullRequestPresentation.rows(scan: scan)
    }

    private var sections: HyperlitePullRequestPinning.Sections {
        pins.sections(for: sourceRows)
    }

    private var projectSections: [HyperliteProjectSection] {
        HyperlitePullRequestSectionPlan.sections(scan: scan, groups: sections.unpinnedGroups)
    }

    private var visibleProjectSections: [HyperliteProjectSection] {
        HyperliteOpenPRProjectFilter.visibleSections(
            projectSections, hideIdle: hideIdleProjects, now: chipClock
        )
    }

    private var hiddenProjectCount: Int {
        projectSections.count - visibleProjectSections.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if scan.projects.isEmpty {
                Text("No configured projects")
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .padding(.vertical, 2)
            } else {
                LazyVStack(alignment: .leading, spacing: 3) {
                    pinnedHeader
                    if sections.pinned.isEmpty {
                        HyperlitePinnedSectionDropTarget(
                            draggedRowID: $draggedRowID,
                            pin: pins.pin
                        )
                    }
                    ForEach(sections.pinned) { row in
                        pullRequestRow(row, pinned: true)
                    }
                    ForEach(visibleProjectSections) { section in
                        HyperliteProjectSectionHeader(
                            section: section,
                            chips: chips(for: section),
                            compact: compactRows,
                            draggedRowID: $draggedRowID,
                            drop: { dropped in
                                if let first = section.rows.first {
                                    pins.move(dropped, over: first.id, rows: sourceRows)
                                } else {
                                    pins.unpin(dropped)
                                }
                            }
                        )
                        if section.rows.isEmpty {
                            HyperliteProjectIdleRow(section: section)
                        }
                        ForEach(section.rows) { row in
                            pullRequestRow(row, pinned: false)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open pull requests across configured projects")
        .accessibilityValue(accessibilityValue)
        .task(id: scan.generatedAt) {
            organization.reconcilePullRequestReviewMarks(scan: scan)
            await advanceChipClock()
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if isRefreshing { parts.append(HyperliteOpenPRRefreshPulse.accessibilityRefreshing) }
        if isPollingActivity { parts.append(HyperliteWorkflowRunGlide.accessibilityPolling) }
        return parts.joined(separator: ". ")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            HyperliteOpenPRTitleCluster(
                count: sourceRows.count
            )
            Spacer()
            Text(HyperlitePullRequestPresentation.freshnessLabel(
                observedAt: scan.observedAt
            ))
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
        }
    }

    private func chips(for section: HyperliteProjectSection) -> [HyperliteWorkflowChip] {
        HyperliteWorkflowStripPresentation.chips(activity: section.project.workflows, now: chipClock)
    }

    /// Re-renders once each time a fresh running chip would turn stale, so a
    /// hidden or denied poll cannot leave the ghost gliding on old data.
    private func advanceChipClock() async {
        chipClock = Date()
        while let expiry = HyperliteWorkflowStripPresentation.nextFreshnessExpiry(scan: scan, now: chipClock) {
            let delay = expiry.timeIntervalSince(Date())
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            chipClock = Date()
        }
    }

    private var pinnedHeader: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("Pinned")
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                Text("\(sections.pinned.count)")
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pinned pull requests, \(sections.pinned.count)")
            Spacer(minLength: 4)
            if hiddenProjectCount > 0 {
                Text("\(hiddenProjectCount) hidden")
                    .font(HyperliteTypography.compact.monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .accessibilityHidden(true)
            }
            HyperliteDashboardControlButton(
                systemName: hideIdleProjects ? "eye.slash" : "eye",
                active: hideIdleProjects,
                label: hideIdleProjects
                    ? "Showing only projects with open pull requests or active workflows. Show all projects."
                    : "Hide projects with no open pull requests"
            ) { hideIdleProjects.toggle() }
        }
        .padding(.top, 2)
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
            togglePin: { pinned ? pins.unpin(row.id) : pins.pin(row.id) },
            move: { pins.move($0, over: $1, rows: sourceRows) },
            moveBy: { pins.move($0, by: $1, rows: sourceRows) }
        )
    }
}
