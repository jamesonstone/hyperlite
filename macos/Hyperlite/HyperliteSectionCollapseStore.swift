import Combine
import Foundation

/// Which Open PRs project sections are collapsed. One published store, so the
/// list, keyboard navigation, and Command-P jumps always agree on what is on
/// screen. Persists per project under the same keys as before.
@MainActor
final class HyperliteSectionCollapseStore: ObservableObject {
    static let shared = HyperliteSectionCollapseStore()

    @Published private(set) var collapsed: Set<String> = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let prefix = HyperliteOpenPRProjectSectionPresentation.storageKey(projectID: "")
        collapsed = Set(defaults.dictionaryRepresentation().compactMap { key, value in
            guard key.hasPrefix(prefix), (value as? Bool) == true else { return nil }
            return String(key.dropFirst(prefix.count))
        })
    }

    func isCollapsed(_ sectionID: String) -> Bool {
        collapsed.contains(sectionID)
    }

    func setCollapsed(_ sectionID: String, _ value: Bool) {
        guard collapsed.contains(sectionID) != value else { return }
        if value { collapsed.insert(sectionID) } else { collapsed.remove(sectionID) }
        defaults.set(value, forKey: HyperliteOpenPRProjectSectionPresentation.storageKey(projectID: sectionID))
    }

    func toggle(_ sectionID: String) {
        setCollapsed(sectionID, !isCollapsed(sectionID))
    }
}
