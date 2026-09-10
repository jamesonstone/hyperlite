import Foundation

enum HyperlitePullRequestPinning {
    struct ProjectGroup: Equatable, Identifiable {
        var repository: String
        var rows: [HyperlitePullRequestRow]
        var id: String { repository }
    }

    struct Sections: Equatable {
        var pinned: [HyperlitePullRequestRow]
        var unpinned: [HyperlitePullRequestRow]
        var unpinnedGroups: [ProjectGroup] { grouped(unpinned) }
    }

    static func grouped(_ rows: [HyperlitePullRequestRow]) -> [ProjectGroup] {
        var groups: [ProjectGroup] = []
        var index: [String: Int] = [:]
        for row in rows {
            if let existing = index[row.repository] {
                groups[existing].rows.append(row)
            } else {
                index[row.repository] = groups.count
                groups.append(ProjectGroup(repository: row.repository, rows: [row]))
            }
        }
        return groups
    }

    static func sections(
        rows: [HyperlitePullRequestRow],
        pinnedIDs: [String],
        unpinnedIDs: [String]
    ) -> Sections {
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let current = Set(byID.keys)
        var seen = Set<String>()
        let pinned = pinnedIDs.compactMap { id -> HyperlitePullRequestRow? in
            guard current.contains(id), seen.insert(id).inserted else { return nil }
            return byID[id]
        }
        let pinnedSet = Set(pinned.map(\.id))
        var unpinnedSeen = Set<String>()
        let remembered = unpinnedIDs.compactMap { id -> HyperlitePullRequestRow? in
            guard current.contains(id), !pinnedSet.contains(id),
                  unpinnedSeen.insert(id).inserted
            else { return nil }
            return byID[id]
        }
        let rememberedSet = Set(remembered.map(\.id))
        let fresh = rows.filter { !pinnedSet.contains($0.id) && !rememberedSet.contains($0.id) }
        return Sections(pinned: pinned, unpinned: fresh + remembered)
    }

    static func move(
        _ id: String,
        over targetID: String,
        pinned: inout [String],
        unpinned: inout [String],
        repositories: [String: String] = [:]
    ) {
        guard id != targetID else { return }
        if pinned.contains(targetID) || repositories.isEmpty {
            remove(id, from: &pinned)
            remove(id, from: &unpinned)
            if pinned.contains(targetID) {
                insert(id, over: targetID, in: &pinned)
            } else {
                insert(id, over: targetID, in: &unpinned)
            }
            return
        }
        remove(id, from: &pinned)
        if unpinned.contains(id) {
            var groups = idGroups(unpinned, repositories: repositories)
            relocate(id, over: targetID, in: &groups, repositories: repositories)
            unpinned = groups.flatMap(\.ids)
            return
        }
        var groups = idGroups(unpinned, repositories: repositories)
        place(id, over: targetID, in: &groups, repositories: repositories)
        unpinned = groups.flatMap(\.ids)
    }

    static func move(_ id: String, intoPinned pinned: inout [String], unpinned: inout [String]) {
        remove(id, from: &unpinned)
        if !pinned.contains(id) {
            pinned.append(id)
        }
    }

    static func move(
        _ id: String,
        by offset: Int,
        pinned: inout [String],
        unpinned: inout [String],
        repositories: [String: String] = [:]
    ) {
        if repositories.isEmpty {
            moveFlat(id, by: offset, pinned: &pinned, unpinned: &unpinned)
            return
        }
        moveGrouped(id, by: offset, pinned: &pinned, unpinned: &unpinned, repositories: repositories)
    }

    private struct IDGroup {
        var repository: String
        var ids: [String]
    }

    private static func idGroups(
        _ ids: [String],
        repositories: [String: String]
    ) -> [IDGroup] {
        var groups: [IDGroup] = []
        var index: [String: Int] = [:]
        for id in ids {
            let repo = repositories[id] ?? id
            if let existing = index[repo] {
                groups[existing].ids.append(id)
            } else {
                index[repo] = groups.count
                groups.append(IDGroup(repository: repo, ids: [id]))
            }
        }
        return groups
    }

    private static func relocate(
        _ id: String,
        over targetID: String,
        in groups: inout [IDGroup],
        repositories: [String: String]
    ) {
        let sourceRepo = repositories[id] ?? id
        let targetRepo = repositories[targetID] ?? targetID
        if sourceRepo == targetRepo {
            guard let groupIndex = groups.firstIndex(where: { $0.repository == sourceRepo }) else {
                return
            }
            groups[groupIndex].ids.removeAll { $0 == id }
            let target = groups[groupIndex].ids.firstIndex(of: targetID)
                ?? groups[groupIndex].ids.endIndex
            groups[groupIndex].ids.insert(id, at: target)
            return
        }
        moveGroup(sourceRepo, before: targetRepo, in: &groups)
    }

    private static func moveGroup(
        _ sourceRepo: String,
        before targetRepo: String,
        in groups: inout [IDGroup]
    ) {
        guard let sourceIndex = groups.firstIndex(where: { $0.repository == sourceRepo }),
              let targetIndex = groups.firstIndex(where: { $0.repository == targetRepo }),
              sourceIndex != targetIndex
        else { return }
        let group = groups.remove(at: sourceIndex)
        let adjusted = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        groups.insert(group, at: adjusted)
    }

    private static func place(
        _ id: String,
        over targetID: String,
        in groups: inout [IDGroup],
        repositories: [String: String]
    ) {
        let sourceRepo = repositories[id] ?? id
        let targetRepo = repositories[targetID] ?? targetID
        if sourceRepo == targetRepo {
            if let groupIndex = groups.firstIndex(where: { $0.repository == sourceRepo }) {
                let target = groups[groupIndex].ids.firstIndex(of: targetID)
                    ?? groups[groupIndex].ids.endIndex
                groups[groupIndex].ids.insert(id, at: target)
            } else {
                groups.insert(IDGroup(repository: sourceRepo, ids: [id]), at: 0)
            }
            return
        }
        if let sourceIndex = groups.firstIndex(where: { $0.repository == sourceRepo }) {
            groups[sourceIndex].ids.insert(id, at: 0)
        } else {
            let insertAt = groups.firstIndex(where: { $0.repository == targetRepo }) ?? 0
            groups.insert(IDGroup(repository: sourceRepo, ids: [id]), at: insertAt)
        }
        moveGroup(sourceRepo, before: targetRepo, in: &groups)
    }

    private static func moveGrouped(
        _ id: String,
        by offset: Int,
        pinned: inout [String],
        unpinned: inout [String],
        repositories: [String: String]
    ) {
        if let index = pinned.firstIndex(of: id) {
            if index + offset >= pinned.count && offset > 0 {
                pinned.remove(at: index)
                unpinned.insert(id, at: 0)
                unpinned = idGroups(unpinned, repositories: repositories).flatMap(\.ids)
                return
            }
            if index + offset < 0 { return }
            move(id, by: offset, in: &pinned)
            return
        }
        var groups = idGroups(unpinned, repositories: repositories)
        guard let groupIndex = groups.firstIndex(where: { $0.ids.contains(id) }),
              let itemIndex = groups[groupIndex].ids.firstIndex(of: id)
        else { return }
        if offset < 0 && itemIndex == 0 {
            if groupIndex == 0 {
                groups[groupIndex].ids.remove(at: itemIndex)
                unpinned = groups.flatMap(\.ids)
                pinned.append(id)
                return
            }
            groups.swapAt(groupIndex, groupIndex - 1)
            unpinned = groups.flatMap(\.ids)
            return
        }
        if offset > 0 && itemIndex == groups[groupIndex].ids.count - 1 {
            if groupIndex + 1 < groups.count {
                groups.swapAt(groupIndex, groupIndex + 1)
                unpinned = groups.flatMap(\.ids)
            }
            return
        }
        move(id, by: offset, in: &groups[groupIndex].ids)
        unpinned = groups.flatMap(\.ids)
    }

    private static func moveFlat(
        _ id: String,
        by offset: Int,
        pinned: inout [String],
        unpinned: inout [String]
    ) {
        if let index = pinned.firstIndex(of: id) {
            if index + offset >= pinned.count && offset > 0 {
                pinned.remove(at: index)
                unpinned.insert(id, at: 0)
                return
            }
            if index + offset < 0 { return }
            move(id, by: offset, in: &pinned)
            return
        }
        if let index = unpinned.firstIndex(of: id) {
            if index + offset < 0 && offset < 0 {
                unpinned.remove(at: index)
                pinned.append(id)
                return
            }
            move(id, by: offset, in: &unpinned)
        }
    }

    private static func remove(_ id: String, from order: inout [String]) {
        order.removeAll { $0 == id }
    }

    private static func insert(_ id: String, over targetID: String, in order: inout [String]) {
        guard let target = order.firstIndex(of: targetID) else {
            order.append(id)
            return
        }
        order.insert(id, at: target)
    }

    private static func move(_ id: String, by offset: Int, in order: inout [String]) {
        guard let source = order.firstIndex(of: id) else { return }
        let target = min(max(0, source + offset), order.count - 1)
        guard source != target else { return }
        let value = order.remove(at: source)
        order.insert(value, at: target)
    }
}
