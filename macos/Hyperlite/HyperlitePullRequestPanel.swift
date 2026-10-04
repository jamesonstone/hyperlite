import SwiftUI

struct HyperlitePullRequestPanel: View {
    let scan: HyperliteProjectPullRequestScan
    @ObservedObject var organization: HyperliteDashboardListState
    var isRefreshing = false
    var isPollingActivity = false
    var selectionID: String?
    var onNavItems: ([HyperliteWorkspaceNavItem]) -> Void = { _ in }
    var onToggleIgnore: (HyperliteProjectPullRequests) -> Void = { _ in }
    @State private var chipClock = Date()
    @AppStorage("hyperlite.dashboard.open-pr-hide-idle") private var hideIdleProjects = true
    @AppStorage(HyperliteHiddenProjectListPresentation.expandedStorageKey)
    private var quietOnesExpanded = false

    @State private var modelCache = HyperlitePullRequestPanelModelCache()

    private var model: HyperlitePullRequestPanelModel {
        modelCache.model(scan: scan, hideIdle: hideIdleProjects, now: chipClock)
    }

    private var visibleProjectSections: [HyperliteProjectSection] { model.visibleSections }
    private var hiddenProjectSections: [HyperliteProjectSection] { model.hiddenSections }
    private var showsHiddenList: Bool { !model.hiddenSections.isEmpty }
    private var hiddenAttentionCount: Int { model.hiddenAttentionCount }

    /// Navigable entries in render order so keyboard selection tracks the list.
    /// Collapsed project rows are skipped because they are not on screen.
    private var navItems: [HyperliteWorkspaceNavItem] {
        var items: [HyperliteWorkspaceNavItem] = []
        for section in visibleProjectSections {
            items.append(navHeaderItem(section))
            if !isCollapsed(section) {
                for row in section.rows {
                    items.append(HyperliteWorkspaceNavItem(id: row.id, action: .open(row.url)))
                }
            }
        }
        if showsHiddenList {
            items.append(HyperliteWorkspaceNavItem(
                id: HyperliteWorkspaceNavigation.quietOnesID, action: .toggleQuietOnes
            ))
            if quietOnesExpanded {
                for section in hiddenProjectSections { items.append(navHeaderItem(section)) }
            }
        }
        return items
    }

    private func navHeaderItem(_ section: HyperliteProjectSection) -> HyperliteWorkspaceNavItem {
        HyperliteWorkspaceNavItem(
            id: headerID(section), action: .open(section.repositoryURL ?? section.pullsURL)
        )
    }

    private func headerID(_ section: HyperliteProjectSection) -> String {
        HyperliteWorkspaceNavigation.headerID(sectionID: section.id)
    }

    private func isCollapsed(_ section: HyperliteProjectSection) -> Bool {
        UserDefaults.standard.bool(
            forKey: HyperliteOpenPRProjectSectionPresentation.storageKey(projectID: section.id)
        )
    }

    private func isSelected(_ id: String) -> Bool { selectionID == id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if scan.projects.isEmpty {
                Text("No configured projects")
                    .font(HyperliteTypography.compact)
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .padding(.vertical, 2)
            } else {
                // Lazy so sections scrolled out of view are not built or laid out.
                LazyVStack(alignment: .leading, spacing: HyperliteOpenPRSpacing.stageSpacing) {
                    ForEach(visibleProjectSections) { section in
                        projectSectionStage(section)
                            .id(section.id)
                    }
                    if showsHiddenList {
                        HyperliteHiddenProjectList(
                            count: hiddenProjectSections.count,
                            attentionCount: hiddenAttentionCount,
                            selected: isSelected(HyperliteWorkspaceNavigation.quietOnesID)
                        ) {
                            ForEach(hiddenProjectSections) { section in
                                projectSectionStage(section)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open pull requests across configured projects")
        .accessibilityValue(accessibilityValue)
        .onChange(of: navItems) { items in
            onNavItems(items)
        }
        .onAppear { onNavItems(navItems) }
        .task(id: scan.generatedAt) {
            organization.reconcilePullRequestReviewMarks(scan: scan)
            await advanceChipClock()
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if isRefreshing { parts.append(HyperliteOpenPRRefreshStatus.accessibilityRefreshing) }
        if isPollingActivity { parts.append(HyperliteOpenPRRefreshStatus.accessibilityPolling) }
        return parts.joined(separator: ". ")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            HyperliteOpenPRTitleCluster(
                count: model.rowCount,
                isRefreshing: isRefreshing
            )
            .layoutPriority(1)
            Spacer(minLength: 4)
            HyperliteHideIdleEye(hideIdle: $hideIdleProjects, hiddenSections: hiddenProjectSections)
            Text(HyperlitePullRequestPresentation.freshnessLabel(
                observedAt: scan.observedAt
            ))
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .lineLimit(1)
                .layoutPriority(-1)
        }
    }

    private func chips(for section: HyperliteProjectSection) -> [HyperliteWorkflowChip] {
        HyperliteWorkflowStripPresentation.chips(activity: section.project.workflows, now: chipClock)
    }

    /// Re-renders once each time a fresh running chip would turn stale, so a
    /// hidden or denied poll cannot leave a chip showing running on old data.
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

    @ViewBuilder
    private func projectSectionStage(_ section: HyperliteProjectSection) -> some View {
        HyperliteOpenPRProjectSection(
            section: section,
            chips: chips(for: section),
            headerSelected: isSelected(headerID(section)),
            onToggleIgnore: { onToggleIgnore(section.project) }
        ) {
            ForEach(section.rows) { row in
                pullRequestRow(row)
                    .hyperliteNavHighlight(selected: isSelected(row.id))
                    .id(row.id)
            }
        }
    }

    private func pullRequestRow(_ row: HyperlitePullRequestRow) -> some View {
        HyperlitePullRequestPanelRow(
            row: row,
            reviewStatus: organization.pullRequestReviewStatus(for: row),
            toggleReview: { organization.togglePullRequestReviewed(row) }
        )
    }
}
