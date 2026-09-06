import Foundation

enum HyperlitePullRequestPinning {
    struct Sections: Equatable {
        var pinned: [HyperlitePullRequestRow]
        var unpinned: [HyperlitePullRequestRow]
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
        unpinned: inout [String]
    ) {
        guard id != targetID else { return }
        let targetPinned = pinned.contains(targetID)
        remove(id, from: &pinned)
        remove(id, from: &unpinned)
        if targetPinned {
            insert(id, over: targetID, in: &pinned)
        } else {
            insert(id, over: targetID, in: &unpinned)
        }
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
