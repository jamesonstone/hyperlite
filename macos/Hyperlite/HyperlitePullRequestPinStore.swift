import Combine
import Foundation

@MainActor
final class HyperlitePullRequestPinStore: ObservableObject {
    @Published private(set) var pinnedIDs: [String]
    @Published private(set) var unpinnedIDs: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinnedIDs = defaults.stringArray(forKey: Keys.pinned) ?? []
        unpinnedIDs = defaults.stringArray(forKey: Keys.unpinned) ?? []
    }

    func sections(for rows: [HyperlitePullRequestRow]) -> HyperlitePullRequestPinning.Sections {
        HyperlitePullRequestPinning.sections(
            rows: rows, pinnedIDs: pinnedIDs, unpinnedIDs: unpinnedIDs
        )
    }

    func move(_ id: String, over targetID: String) {
        var pinned = pinnedIDs
        var unpinned = unpinnedIDs
        HyperlitePullRequestPinning.move(
            id, over: targetID, pinned: &pinned, unpinned: &unpinned
        )
        persist(pinned: pinned, unpinned: unpinned)
    }

    func move(_ id: String, by offset: Int) {
        var pinned = pinnedIDs
        var unpinned = unpinnedIDs
        HyperlitePullRequestPinning.move(
            id, by: offset, pinned: &pinned, unpinned: &unpinned
        )
        persist(pinned: pinned, unpinned: unpinned)
    }

    func pin(_ id: String) {
        var pinned = pinnedIDs
        var unpinned = unpinnedIDs
        HyperlitePullRequestPinning.move(id, intoPinned: &pinned, unpinned: &unpinned)
        persist(pinned: pinned, unpinned: unpinned)
    }

    func unpin(_ id: String) {
        var pinned = pinnedIDs
        var unpinned = unpinnedIDs
        pinned.removeAll { $0 == id }
        if !unpinned.contains(id) {
            unpinned.insert(id, at: 0)
        }
        persist(pinned: pinned, unpinned: unpinned)
    }

    private func persist(pinned: [String], unpinned: [String]) {
        pinnedIDs = pinned
        unpinnedIDs = unpinned
        defaults.set(pinned, forKey: Keys.pinned)
        defaults.set(unpinned, forKey: Keys.unpinned)
    }

    private enum Keys {
        static let pinned = "hyperlite.dashboard.open-pr-pinned"
        static let unpinned = "hyperlite.dashboard.open-pr-unpinned"
    }
}
