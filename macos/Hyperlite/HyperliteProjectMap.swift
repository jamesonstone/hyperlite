import SwiftUI
import UniformTypeIdentifiers

struct HyperliteProjectMap: View {
    let projects: [HyperliteProjectLocation]
    let pullRequests: HyperliteProjectPullRequestScan?
    @ObservedObject var organization: HyperliteDashboardListState
    @State private var isFilterPresented = false
    @State private var draggedProjectID: String?

    private var pullRequestCounts: [String: Int] {
        Dictionary(
            (pullRequests?.projects ?? []).map { ($0.id, $0.pullRequests.count) },
            uniquingKeysWith: +
        )
    }

    private var presentedProjects: [HyperliteProjectLocation] {
        let filter = organization.isReorderingProjects
            ? HyperliteProjectFilter() : organization.projectFilter
        let sort = organization.isReorderingProjects
            ? HyperliteProjectSort.custom : organization.projectSort
        return HyperliteDashboardListPresentation.projects(
            projects,
            pullRequestCounts: pullRequestCounts,
            filter: filter,
            sort: sort,
            customOrder: organization.orderedProjectIDs(projects.map(\.id))
        )
    }

    private var countLabel: String {
        if organization.projectFilter.isActive, !organization.isReorderingProjects {
            return "\(presentedProjects.count)/\(projects.count)"
        }
        return "\(projects.count)"
    }

    private var filterIsEffective: Bool {
        organization.projectFilter.isActive && !organization.isReorderingProjects
    }

    private var allPresentedProjectsCollapsed: Bool {
        !presentedProjects.isEmpty && presentedProjects.allSatisfy {
            organization.collapsedProjectIDs.contains($0.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if presentedProjects.isEmpty {
                Text(organization.projectFilter.isActive
                    ? "No matching projects" : "No configured projects")
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .padding(.vertical, 2)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(presentedProjects) { project in
                        HyperliteProjectMapEntry(
                            project: project,
                            openPullRequestCount: pullRequestCounts[project.id] ?? 0,
                            collapsed: organization.isProjectCollapsed(
                                project.id,
                                whileFiltering: filterIsEffective
                            ),
                            collapseDisabled: filterIsEffective,
                            reordering: organization.isReorderingProjects,
                            draggedProjectID: $draggedProjectID,
                            toggleCollapsed: { organization.toggleProject(project.id) },
                            move: organization.moveProject,
                            moveBy: organization.moveProject
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active project branches and worktrees")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("Projects")
                .font(HyperliteTypography.semibold(11))
                .foregroundStyle(HyperliteTheme.secondaryText.color)
            Text(countLabel)
                .font(HyperliteTypography.bold(10).monospacedDigit())
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Spacer()
            if organization.isReorderingProjects {
                Text("Reordering all")
                    .font(HyperliteTypography.regular(10))
                    .foregroundStyle(HyperliteTheme.cyan.color)
                Button("Cancel") {
                    draggedProjectID = nil
                    organization.finishProjectReordering(commit: false)
                }
                Button("Done") {
                    draggedProjectID = nil
                    organization.finishProjectReordering(commit: true)
                }
            } else {
                HyperliteDashboardControlButton(
                    systemName: "rectangle.compress.vertical",
                    active: allPresentedProjectsCollapsed,
                    label: allPresentedProjectsCollapsed
                        ? "Expand all projects" : "Collapse all projects",
                    disabled: filterIsEffective || presentedProjects.isEmpty
                ) {
                    organization.toggleAllProjects(presentedProjects.map(\.id))
                }
                HyperliteDashboardControlButton(
                    systemName: "line.3.horizontal.decrease",
                    active: organization.projectFilter.isActive,
                    label: "Filter projects"
                ) { isFilterPresented.toggle() }
                .popover(isPresented: $isFilterPresented, arrowEdge: .top) {
                    HyperliteProjectFilterPopover(filter: projectFilterBinding)
                }
                projectSortMenu
                HyperliteDashboardControlButton(
                    systemName: "line.3.horizontal",
                    active: organization.projectSort == .custom,
                    label: "Reorder projects",
                    disabled: projects.count < 2
                ) {
                    organization.beginProjectReordering(currentIDs: projects.map(\.id))
                }
            }
            Text("Active branches and worktrees")
                .font(HyperliteTypography.regular(10))
                .foregroundStyle(HyperliteTheme.mutedText.color)
        }
    }

    private var projectSortMenu: some View {
        Menu {
            ForEach(HyperliteProjectSort.allCases) { sort in
                Button {
                    organization.setProjectSort(sort)
                } label: {
                    if organization.projectSort == sort {
                        Label(sort.title, systemImage: "checkmark")
                    } else {
                        Text(sort.title)
                    }
                }
            }
        } label: {
            HyperliteDashboardHeaderIcon(
                systemName: "arrow.up.arrow.down",
                active: organization.projectSort != .configured
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort projects")
        .accessibilityLabel("Sort projects")
    }

    private var projectFilterBinding: Binding<HyperliteProjectFilter> {
        Binding(
            get: { organization.projectFilter },
            set: organization.setProjectFilter
        )
    }
}

private struct HyperliteProjectMapEntry: View {
    let project: HyperliteProjectLocation
    let openPullRequestCount: Int
    let collapsed: Bool
    let collapseDisabled: Bool
    let reordering: Bool
    @Binding var draggedProjectID: String?
    let toggleCollapsed: () -> Void
    let move: (String, String) -> Void
    let moveBy: (String, Int) -> Void

    private var firstLane: HyperliteProjectLane? { project.lanes.first }
    private var remainingLanes: [HyperliteProjectLane] { Array(project.lanes.dropFirst()) }
    private var worktreeCount: Int { project.lanes.filter { !$0.primary }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if reordering { dragHandle }
                projectIdentity
                laneMetadata(firstLane, collapsed: collapsed)
            }
            if !collapsed {
                ForEach(remainingLanes) { lane in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        if reordering { Color.clear.frame(width: 16) }
                        Color.clear.frame(width: 190)
                        laneMetadata(lane, collapsed: false)
                    }
                }
            }
        }
        .font(HyperliteTypography.regular(10))
        .foregroundStyle(HyperliteTheme.secondaryText.color)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.text.identifier],
            delegate: HyperliteReorderDropDelegate(
                targetID: project.id,
                draggedID: $draggedProjectID,
                move: move
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name), \(collapsed ? "collapsed" : "expanded"), " +
            "\(worktreeCount) active worktrees, \(openPullRequestCount) open pull requests")
        .modifier(HyperliteReorderAccessibilityModifier(
            enabled: reordering,
            id: project.id,
            moveBy: moveBy
        ))
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(HyperliteTheme.mutedText.color)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onDrag {
                draggedProjectID = project.id
                return NSItemProvider(object: project.id as NSString)
            }
    }

    private var projectIdentity: some View {
        HStack(spacing: 3) {
            Button(action: toggleCollapsed) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .frame(width: 12, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(collapseDisabled)
            .help(collapseDisabled ? "Clear filters to collapse projects" :
                (collapsed ? "Expand \(project.name)" : "Collapse \(project.name)"))
            .accessibilityLabel(collapsed ? "Expand \(project.name)" : "Collapse \(project.name)")
            Text(project.name)
                .font(HyperliteTypography.medium(10))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 190, alignment: .leading)
    }

    @ViewBuilder
    private func laneMetadata(_ lane: HyperliteProjectLane?, collapsed: Bool) -> some View {
        if let lane {
            Text(HyperliteProjectIndexPresentation.laneKind(lane))
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
            Text(HyperliteProjectIndexPresentation.laneLabel(lane))
                .frame(width: 86, alignment: .leading)
                .lineLimit(1)
            if collapsed {
                Text("\(worktreeCount) worktree\(worktreeCount == 1 ? "" : "s") · " +
                    "\(openPullRequestCount) PR\(openPullRequestCount == 1 ? "" : "s")")
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            } else {
                Text(HyperliteProjectIndexPresentation.abbreviatedPath(lane.path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(lane.path)
            }
        } else {
            Text("unavailable")
                .frame(width: 151, alignment: .leading)
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Text(HyperliteProjectIndexPresentation.abbreviatedPath(project.path))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(project.path)
        }
        Spacer(minLength: 0)
    }
}
