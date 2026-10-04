import SwiftUI

/// The whole Open PRs pane: a top bar of quick facts and window actions, the
/// pull request list with pinned project headers, and a footer. The list is a
/// LazyVStack that is the ScrollView's direct content, so only rows on screen
/// are built, headers pin natively, and scrolling to an entry is exact.
struct HyperlitePullRequestPanel<Actions: View>: View {
    let scan: HyperliteProjectPullRequestScan
    @ObservedObject var organization: HyperliteDashboardListState
    var isRefreshing = false
    var isPollingActivity = false
    var errorMessage: String?
    var selectionID: String?
    var scrollRequest: HyperliteScrollRequest?
    var detailsID: String?
    var onCloseDetails: () -> Void = {}
    var onNavItems: ([HyperliteWorkspaceNavItem]) -> Void = { _ in }
    var onToggleIgnore: (HyperliteProjectPullRequests) -> Void = { _ in }
    @ViewBuilder var actions: Actions
    @ObservedObject private var collapse = HyperliteSectionCollapseStore.shared
    @State private var chipClock = Date()
    @State private var modelCache = HyperlitePullRequestPanelModelCache()
    @AppStorage("hyperlite.dashboard.open-pr-hide-idle") private var hideIdleProjects = true

    private var model: HyperlitePullRequestPanelModel {
        modelCache.model(scan: scan, hideIdle: hideIdleProjects, now: chipClock)
    }

    var body: some View {
        let model = model
        VStack(alignment: .leading, spacing: 0) {
            topBar(model)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(HyperliteTypography.body)
                    .foregroundStyle(HyperliteTheme.red.color)
                    .padding(.bottom, 6)
            }
            list(model)
            HyperliteOpenPRFooter(observedAt: scan.observedAt)
        }
        .onChange(of: navItems(model)) { onNavItems($0) }
        .onAppear { onNavItems(navItems(model)) }
        .task(id: scan.generatedAt) {
            organization.reconcilePullRequestReviewMarks(scan: scan)
            await advanceChipClock()
        }
    }

    private func topBar(_ model: HyperlitePullRequestPanelModel) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HyperliteQuickFactsBar(facts: HyperliteQuickFacts.facts(model: model, now: chipClock))
                .layoutPriority(1)
            if isRefreshing {
                ProgressView().controlSize(.mini).accessibilityLabel(HyperliteOpenPRRefreshStatus.accessibilityRefreshing)
            }
            Spacer(minLength: 4)
            HyperliteHideIdleEye(hideIdle: $hideIdleProjects, hiddenSections: model.hiddenSections)
            actions
        }
        .padding(.bottom, 8)
    }

    private func list(_ model: HyperlitePullRequestPanelModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if model.sections.isEmpty {
                        Text("No configured projects")
                            .font(HyperliteTypography.compact)
                            .foregroundStyle(HyperliteTheme.mutedText.color)
                    }
                    ForEach(model.organizations) { organization in
                        HyperliteOrganizationHeading(group: organization)
                        ForEach(organization.sections) { section in
                            Section {
                                if !collapse.isCollapsed(section.id) {
                                    ForEach(section.rows) { row in
                                        pullRequestRow(row)
                                    }
                                }
                            } header: {
                                sectionHeader(section)
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .onChange(of: scrollRequest) { request in
                guard let request else { return }
                // Keep the keyboard selection in the middle of the list.
                proxy.scrollTo(request.id, anchor: .center)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Open pull requests across configured projects")
            .accessibilityValue(isPollingActivity ? HyperliteOpenPRRefreshStatus.accessibilityPolling : "")
        }
    }

    private func sectionHeader(_ section: HyperliteProjectSection) -> some View {
        let chips = HyperliteWorkflowStripPresentation.chips(activity: section.project.workflows, now: chipClock)
        let id = HyperliteWorkspaceNavigation.headerID(sectionID: section.id)
        return HyperliteProjectSectionHeader(
            section: section,
            chips: chips,
            collapsed: HyperliteOpenPRProjectSectionPresentation.canCollapse(section) ? Binding(
                get: { collapse.isCollapsed(section.id) },
                set: { collapse.setCollapsed(section.id, $0) }
            ) : nil,
            onToggleIgnore: { onToggleIgnore(section.project) },
            stageKind: .forSection(
                section, chips: chips,
                alerts: HyperlitePipelineAlertPresentation.alerts(from: section.project.workflows)
            )
        )
        .padding(.vertical, 4)
        .hyperliteNavHighlight(selected: selectionID == id)
        .background(HyperliteTheme.canvas.color)
        .id(id)
    }

    private func pullRequestRow(_ row: HyperlitePullRequestRow) -> some View {
        HyperlitePullRequestPanelRow(
            row: row,
            reviewStatus: organization.pullRequestReviewStatus(for: row),
            toggleReview: { organization.togglePullRequestReviewed(row) },
            keyboardDetails: detailsID == row.id,
            onCloseDetails: onCloseDetails
        )
        .frame(height: HyperliteOpenPRSpacing.rowHeight(bodySize: HyperliteAppearance.shared.bodySize))
        .padding(.vertical, HyperliteOpenPRSpacing.rowVerticalPadding)
        .hyperliteNavHighlight(selected: selectionID == row.id)
        .id(row.id)
    }

    /// Navigable entries in render order; collapsed rows are skipped.
    private func navItems(_ model: HyperlitePullRequestPanelModel) -> [HyperliteWorkspaceNavItem] {
        var items: [HyperliteWorkspaceNavItem] = []
        for section in model.organizations.flatMap(\.sections) {
            items.append(HyperliteWorkspaceNavItem(
                id: HyperliteWorkspaceNavigation.headerID(sectionID: section.id),
                action: .open(section.repositoryURL ?? section.pullsURL)
            ))
            guard !collapse.isCollapsed(section.id) else { continue }
            for row in section.rows {
                items.append(HyperliteWorkspaceNavItem(id: row.id, action: .open(row.url)))
            }
        }
        return items
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
}
