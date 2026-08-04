import Combine
import Foundation

@MainActor
final class HyperliteDashboardListState: ObservableObject {
    @Published private(set) var pullRequestSort: HyperlitePullRequestSort
    @Published private(set) var projectSort: HyperliteProjectSort
    @Published private(set) var pullRequestFilter = HyperlitePullRequestFilter()
    @Published private(set) var projectFilter = HyperliteProjectFilter()
    @Published private(set) var collapsedProjectIDs: Set<String>
    @Published private(set) var isReorderingPullRequests = false
    @Published private(set) var isReorderingProjects = false

    private let defaults: UserDefaults
    private var pullRequestOrder: [String]
    private var projectOrder: [String]
    private var pullRequestDraft: [String]?
    private var projectDraft: [String]?
    private var pullRequestSnapshot: (HyperlitePullRequestSort, [String])?
    private var projectSnapshot: (HyperliteProjectSort, [String])?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pullRequestSort = HyperlitePullRequestSort(
            rawValue: defaults.string(forKey: Keys.pullRequestSort) ?? ""
        ) ?? .recent
        projectSort = HyperliteProjectSort(
            rawValue: defaults.string(forKey: Keys.projectSort) ?? ""
        ) ?? .configured
        pullRequestOrder = defaults.stringArray(forKey: Keys.pullRequestOrder) ?? []
        projectOrder = defaults.stringArray(forKey: Keys.projectOrder) ?? []
        collapsedProjectIDs = Set(defaults.stringArray(forKey: Keys.collapsedProjects) ?? [])
    }

    func setPullRequestFilter(_ filter: HyperlitePullRequestFilter) {
        pullRequestFilter = filter
    }

    func clearPullRequestFilter() {
        pullRequestFilter = HyperlitePullRequestFilter()
    }

    func setProjectFilter(_ filter: HyperliteProjectFilter) {
        projectFilter = filter
    }

    func clearProjectFilter() {
        projectFilter = HyperliteProjectFilter()
    }

    func setPullRequestSort(_ sort: HyperlitePullRequestSort) {
        guard !isReorderingPullRequests else { return }
        pullRequestSort = sort
        defaults.set(sort.rawValue, forKey: Keys.pullRequestSort)
    }

    func setProjectSort(_ sort: HyperliteProjectSort) {
        guard !isReorderingProjects else { return }
        projectSort = sort
        defaults.set(sort.rawValue, forKey: Keys.projectSort)
    }

    func orderedPullRequestIDs(_ currentIDs: [String]) -> [String] {
        if let pullRequestDraft { return pullRequestDraft }
        return HyperliteDashboardListPresentation.normalizedOrder(
            currentIDs: currentIDs,
            storedOrder: pullRequestOrder,
            newItems: .beforeKnown
        )
    }

    func orderedProjectIDs(_ currentIDs: [String]) -> [String] {
        if let projectDraft { return projectDraft }
        return HyperliteDashboardListPresentation.normalizedOrder(
            currentIDs: currentIDs,
            storedOrder: projectOrder,
            newItems: .afterKnown
        )
    }

    func beginPullRequestReordering(currentIDs: [String]) {
        guard !isReorderingPullRequests else { return }
        pullRequestSnapshot = (pullRequestSort, pullRequestOrder)
        pullRequestDraft = HyperliteDashboardListPresentation.normalizedOrder(
            currentIDs: currentIDs,
            storedOrder: pullRequestOrder,
            newItems: .beforeKnown
        )
        isReorderingPullRequests = true
    }

    func finishPullRequestReordering(commit: Bool) {
        guard isReorderingPullRequests else { return }
        if commit, let pullRequestDraft {
            pullRequestOrder = pullRequestDraft
            pullRequestSort = .custom
            defaults.set(pullRequestOrder, forKey: Keys.pullRequestOrder)
            defaults.set(pullRequestSort.rawValue, forKey: Keys.pullRequestSort)
        } else if let pullRequestSnapshot {
            pullRequestSort = pullRequestSnapshot.0
            pullRequestOrder = pullRequestSnapshot.1
        }
        pullRequestDraft = nil
        pullRequestSnapshot = nil
        isReorderingPullRequests = false
    }

    func movePullRequest(_ id: String, over targetID: String) {
        guard var draft = pullRequestDraft else { return }
        move(id, over: targetID, in: &draft)
        pullRequestDraft = draft
        objectWillChange.send()
    }

    func movePullRequest(_ id: String, by offset: Int) {
        guard var draft = pullRequestDraft else { return }
        move(id, by: offset, in: &draft)
        pullRequestDraft = draft
        objectWillChange.send()
    }

    func beginProjectReordering(currentIDs: [String]) {
        guard !isReorderingProjects else { return }
        projectSnapshot = (projectSort, projectOrder)
        projectDraft = HyperliteDashboardListPresentation.normalizedOrder(
            currentIDs: currentIDs,
            storedOrder: projectOrder,
            newItems: .afterKnown
        )
        isReorderingProjects = true
    }

    func finishProjectReordering(commit: Bool) {
        guard isReorderingProjects else { return }
        if commit, let projectDraft {
            projectOrder = projectDraft
            projectSort = .custom
            defaults.set(projectOrder, forKey: Keys.projectOrder)
            defaults.set(projectSort.rawValue, forKey: Keys.projectSort)
        } else if let projectSnapshot {
            projectSort = projectSnapshot.0
            projectOrder = projectSnapshot.1
        }
        projectDraft = nil
        projectSnapshot = nil
        isReorderingProjects = false
    }

    func moveProject(_ id: String, over targetID: String) {
        guard var draft = projectDraft else { return }
        move(id, over: targetID, in: &draft)
        projectDraft = draft
        objectWillChange.send()
    }

    func moveProject(_ id: String, by offset: Int) {
        guard var draft = projectDraft else { return }
        move(id, by: offset, in: &draft)
        projectDraft = draft
        objectWillChange.send()
    }

    func isProjectCollapsed(_ id: String, whileFiltering: Bool) -> Bool {
        !whileFiltering && collapsedProjectIDs.contains(id)
    }

    func toggleProject(_ id: String) {
        if collapsedProjectIDs.contains(id) {
            collapsedProjectIDs.remove(id)
        } else {
            collapsedProjectIDs.insert(id)
        }
        persistCollapsedProjects()
    }

    func toggleAllProjects(_ ids: [String]) {
        let visible = Set(ids)
        if !visible.isEmpty, visible.isSubset(of: collapsedProjectIDs) {
            collapsedProjectIDs.subtract(visible)
        } else {
            collapsedProjectIDs.formUnion(visible)
        }
        persistCollapsedProjects()
    }

    private func persistCollapsedProjects() {
        defaults.set(collapsedProjectIDs.sorted(), forKey: Keys.collapsedProjects)
    }

    private func move(_ id: String, over targetID: String, in order: inout [String]) {
        guard id != targetID,
              let source = order.firstIndex(of: id),
              let target = order.firstIndex(of: targetID)
        else { return }
        // Keep the dragged row beyond the row it crossed so adjacent rows swap
        // in either direction. The target index intentionally predates removal.
        let value = order.remove(at: source)
        order.insert(value, at: target)
    }

    private func move(_ id: String, by offset: Int, in order: inout [String]) {
        guard let source = order.firstIndex(of: id) else { return }
        let target = min(max(0, source + offset), order.count - 1)
        guard source != target else { return }
        let value = order.remove(at: source)
        order.insert(value, at: target)
    }

    private enum Keys {
        static let pullRequestSort = "hyperlite.dashboard.open-pr-sort"
        static let projectSort = "hyperlite.dashboard.project-sort"
        static let pullRequestOrder = "hyperlite.dashboard.open-pr-order"
        static let projectOrder = "hyperlite.dashboard.project-order"
        static let collapsedProjects = "hyperlite.dashboard.collapsed-projects"
    }
}
