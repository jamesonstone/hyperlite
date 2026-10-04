import Foundation

/// Everything the Open PRs panel derives from one scan, computed once.
/// Building rows, the section plan, and the hide-idle split is the panel's
/// dominant cost, and its body re-runs on every keyboard selection change.
struct HyperlitePullRequestPanelModel {
    let rowCount: Int
    let sections: [HyperliteProjectSection]
    let visibleSections: [HyperliteProjectSection]
    let hiddenSections: [HyperliteProjectSection]
    let hiddenAttentionCount: Int

    init(scan: HyperliteProjectPullRequestScan, hideIdle: Bool, now: Date) {
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        rowCount = rows.count
        sections = HyperlitePullRequestSectionPlan.sections(scan: scan, rows: rows)
        visibleSections = HyperliteOpenPRProjectFilter.visibleSections(sections, hideIdle: hideIdle, now: now)
        hiddenSections = HyperliteOpenPRProjectFilter.hiddenSections(sections, hideIdle: hideIdle, now: now)
        hiddenAttentionCount = HyperliteOpenPRProjectFilter.attentionCount(hiddenSections, now: now)
    }

    var hiddenCount: Int { sections.count - visibleSections.count }

    /// Visible sections grouped by GitHub organization. Organizations keep
    /// the order of their first visible project, so the org with the most
    /// recently updated pull request leads; project order within an org is
    /// unchanged.
    var organizations: [HyperliteOrganizationGroup] {
        HyperliteOrganizationGroup.groups(visibleSections)
    }
}

struct HyperliteOrganizationGroup: Identifiable, Equatable {
    let name: String
    let sections: [HyperliteProjectSection]

    var id: String { "org:\(name)" }
    var pullRequestCount: Int { sections.reduce(0) { $0 + $1.rows.count } }
    var url: URL? { name == Self.localName ? nil : URL(string: "https://github.com/\(name)") }

    static let localName = "local"

    static func organization(of section: HyperliteProjectSection) -> String {
        let repository = section.project.repository ?? ""
        guard let slash = repository.firstIndex(of: "/"), slash != repository.startIndex else { return localName }
        return String(repository[..<slash]).lowercased()
    }

    static func groups(_ sections: [HyperliteProjectSection]) -> [HyperliteOrganizationGroup] {
        var order: [String] = []
        var members: [String: [HyperliteProjectSection]] = [:]
        for section in sections {
            let name = organization(of: section)
            if members[name] == nil { order.append(name) }
            members[name, default: []].append(section)
        }
        return order.map { HyperliteOrganizationGroup(name: $0, sections: members[$0] ?? []) }
    }
}

/// Memoizes the panel model across body evaluations. A reference type so the
/// view can refresh it during `body` without publishing a state change.
final class HyperlitePullRequestPanelModelCache {
    // Every scan the helper emits carries a fresh generatedAt, so it
    // identifies the scan without a deep comparison on each body pass.
    private struct Key: Equatable {
        let scan: Date
        let hideIdle: Bool
        let now: Date
    }

    private var key: Key?
    private var model: HyperlitePullRequestPanelModel?

    func model(
        scan: HyperliteProjectPullRequestScan,
        hideIdle: Bool,
        now: Date
    ) -> HyperlitePullRequestPanelModel {
        let next = Key(scan: scan.generatedAt, hideIdle: hideIdle, now: now)
        if let model, key == next { return model }
        let built = HyperlitePullRequestPanelModel(scan: scan, hideIdle: hideIdle, now: now)
        key = next
        model = built
        return built
    }
}
