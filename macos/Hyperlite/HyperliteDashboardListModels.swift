import Foundation

enum HyperlitePullRequestSort: String, CaseIterable, Identifiable {
    case recent, repository, review, state, number, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Recently updated"
        case .repository: "Repository"
        case .review: "Review attention"
        case .state: "Ready before drafts"
        case .number: "Pull request number"
        case .custom: "Custom order"
        }
    }
}

enum HyperliteProjectSort: String, CaseIterable, Identifiable {
    case configured, name, worktrees, pullRequests, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .configured: "Configured order"
        case .name: "Project name"
        case .worktrees: "Active worktrees"
        case .pullRequests: "Open pull requests"
        case .custom: "Custom order"
        }
    }
}

enum HyperliteProjectLaneFilter: String, CaseIterable, Identifiable {
    case all, branch, worktree

    var id: String { rawValue }
    var title: String { rawValue == "all" ? "All lanes" : rawValue.capitalized }
}

enum HyperliteProjectActivityFilter: String, CaseIterable, Identifiable {
    case all, worktrees, pullRequests

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All projects"
        case .worktrees: "Has active worktrees"
        case .pullRequests: "Has open pull requests"
        }
    }
}

struct HyperliteProjectFilter: Equatable {
    var query = ""
    var lane: HyperliteProjectLaneFilter = .all
    var activity: HyperliteProjectActivityFilter = .all

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            lane != .all || activity != .all
    }
}

enum HyperliteDashboardListPresentation {
    enum NewItemPlacement { case beforeKnown, afterKnown }

    static func pullRequests(
        _ rows: [HyperlitePullRequestRow],
        filter: HyperlitePullRequestFilter,
        sort: HyperlitePullRequestSort,
        customOrder: [String],
        reviewStatuses: [String: HyperlitePullRequestReviewStatus] = [:]
    ) -> [HyperlitePullRequestRow] {
        let query = normalized(filter.query.trimmingCharacters(in: .whitespacesAndNewlines))
        let filtered = rows.filter { row in
            let queryMatches = query.isEmpty || [
                row.repository, row.title, "#\(row.number)", "\(row.number)",
            ].contains { normalized($0).contains(query) }
            let repositoryMatches = filter.repository.isEmpty ||
                row.repository == filter.repository
            let stateMatches = switch filter.state {
            case .all: true
            case .ready: !row.isDraft
            case .draft: row.isDraft
            }
            let hideDraftMatches = !filter.hideDrafts || !row.isDraft
            let reviewMatches = switch filter.review {
            case .all: true
            case .attention: (row.unresolvedReviewThreads ?? 0) > 0
            case .clear: row.unresolvedReviewThreads == 0
            case .unavailable: row.unresolvedReviewThreads == nil
            }
            let localReviewStatus = reviewStatuses[row.id] ?? .unreviewed
            let localReviewMatches = switch filter.localReview {
            case .all: true
            case .unreviewed: localReviewStatus == .unreviewed
            case .reviewed: localReviewStatus == .reviewed
            case .stale: localReviewStatus == .stale
            }
            let dataMatches = filter.data == .all || row.status.rawValue == filter.data.rawValue
            return queryMatches && repositoryMatches && stateMatches && hideDraftMatches &&
                reviewMatches && localReviewMatches && dataMatches
        }
        return sortedPullRequests(filtered, sort: sort, customOrder: customOrder)
    }

    static func displayedPullRequests(
        _ rows: [HyperlitePullRequestRow],
        filter: HyperlitePullRequestFilter,
        sort: HyperlitePullRequestSort,
        customOrder: [String],
        reviewStatuses: [String: HyperlitePullRequestReviewStatus] = [:],
        isReordering: Bool
    ) -> [HyperlitePullRequestRow] {
        pullRequests(
            rows,
            filter: isReordering ? HyperlitePullRequestFilter() : filter,
            sort: isReordering ? .custom : sort,
            customOrder: customOrder,
            reviewStatuses: reviewStatuses
        )
    }

    static func availability(
        _ projects: [HyperliteProjectPullRequests],
        filter: HyperlitePullRequestFilter
    ) -> [HyperliteProjectPullRequests] {
        guard filter.state == .all, filter.review == .all,
              filter.localReview == .all, !filter.hideDrafts
        else { return [] }
        let query = normalized(filter.query.trimmingCharacters(in: .whitespacesAndNewlines))
        return projects.filter { project in
            let identity = project.repository ?? project.name
            let queryMatches = query.isEmpty || normalized(identity).contains(query)
            let repositoryMatches = filter.repository.isEmpty || identity == filter.repository
            let dataMatches = filter.data == .all || project.status.rawValue == filter.data.rawValue
            return queryMatches && repositoryMatches && dataMatches
        }
    }

    static func projects(
        _ projects: [HyperliteProjectLocation],
        pullRequestCounts: [String: Int],
        filter: HyperliteProjectFilter,
        sort: HyperliteProjectSort,
        customOrder: [String]
    ) -> [HyperliteProjectLocation] {
        let query = normalized(filter.query.trimmingCharacters(in: .whitespacesAndNewlines))
        let worktreeCounts = Dictionary(uniqueKeysWithValues: projects.map {
            ($0.id, $0.lanes.filter { !$0.primary }.count)
        })
        let filtered = projects.compactMap { project -> HyperliteProjectLocation? in
            let hasWorktree = project.lanes.contains { !$0.primary }
            let activityMatches = switch filter.activity {
            case .all: true
            case .worktrees: hasWorktree
            case .pullRequests: (pullRequestCounts[project.id] ?? 0) > 0
            }
            guard activityMatches else { return nil }

            let lanes = project.lanes.filter { lane in
                switch filter.lane {
                case .all: true
                case .branch: lane.primary
                case .worktree: !lane.primary
                }
            }
            guard filter.lane == .all || !lanes.isEmpty else { return nil }

            let projectMatches = query.isEmpty || [project.name, project.repository ?? "", project.path]
                .contains { normalized($0).contains(query) }
            let matchingLanes = query.isEmpty || projectMatches ? lanes : lanes.filter { lane in
                [lane.branch ?? "", lane.path, HyperliteProjectIndexPresentation.laneKind(lane)]
                    .contains { normalized($0).contains(query) }
            }
            guard projectMatches || !matchingLanes.isEmpty else { return nil }
            return HyperliteProjectLocation(
                id: project.id,
                name: project.name,
                path: project.path,
                repository: project.repository,
                lanes: matchingLanes
            )
        }
        return sortedProjects(
            filtered,
            worktreeCounts: worktreeCounts,
            pullRequestCounts: pullRequestCounts,
            sort: sort,
            customOrder: customOrder
        )
    }

    static func normalizedOrder(
        currentIDs: [String],
        storedOrder: [String],
        newItems: NewItemPlacement
    ) -> [String] {
        var seen = Set<String>()
        let current = currentIDs.filter { seen.insert($0).inserted }
        let currentSet = Set(current)
        var knownSeen = Set<String>()
        let known = storedOrder.filter { currentSet.contains($0) && knownSeen.insert($0).inserted }
        let knownSet = Set(known)
        let fresh = current.filter { !knownSet.contains($0) }
        return newItems == .beforeKnown ? fresh + known : known + fresh
    }

    private static func sortedPullRequests(
        _ rows: [HyperlitePullRequestRow],
        sort: HyperlitePullRequestSort,
        customOrder: [String]
    ) -> [HyperlitePullRequestRow] {
        if sort == .custom {
            let order = normalizedOrder(
                currentIDs: rows.map(\.id), storedOrder: customOrder, newItems: .beforeKnown
            )
            let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            return rows.sorted { rank[$0.id, default: .max] < rank[$1.id, default: .max] }
        }
        return rows.sorted { lhs, rhs in
            switch sort {
            case .recent:
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            case .repository:
                let left = normalized(lhs.repository)
                let right = normalized(rhs.repository)
                if left != right { return left < right }
            case .review:
                let left = lhs.unresolvedReviewThreads ?? -1
                let right = rhs.unresolvedReviewThreads ?? -1
                if left != right { return left > right }
            case .state:
                if lhs.isDraft != rhs.isDraft { return !lhs.isDraft }
            case .number:
                if lhs.number != rhs.number { return lhs.number > rhs.number }
            case .custom:
                break
            }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.repository != rhs.repository { return lhs.repository < rhs.repository }
            return lhs.number < rhs.number
        }
    }

    private static func sortedProjects(
        _ projects: [HyperliteProjectLocation],
        worktreeCounts: [String: Int],
        pullRequestCounts: [String: Int],
        sort: HyperliteProjectSort,
        customOrder: [String]
    ) -> [HyperliteProjectLocation] {
        if sort == .configured { return projects }
        if sort == .custom {
            let order = normalizedOrder(
                currentIDs: projects.map(\.id), storedOrder: customOrder, newItems: .afterKnown
            )
            let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            return projects.sorted { rank[$0.id, default: .max] < rank[$1.id, default: .max] }
        }
        return projects.sorted { lhs, rhs in
            switch sort {
            case .name:
                if normalized(lhs.name) != normalized(rhs.name) {
                    return normalized(lhs.name) < normalized(rhs.name)
                }
            case .worktrees:
                let left = worktreeCounts[lhs.id] ?? 0
                let right = worktreeCounts[rhs.id] ?? 0
                if left != right { return left > right }
            case .pullRequests:
                let left = pullRequestCounts[lhs.id] ?? 0
                let right = pullRequestCounts[rhs.id] ?? 0
                if left != right { return left > right }
            case .configured, .custom:
                break
            }
            return normalized(lhs.name) < normalized(rhs.name)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
