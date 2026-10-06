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
    let undeployed: [HyperliteUndeployedProject]

    init(scan: HyperliteProjectPullRequestScan, hideIdle: Bool, now: Date) {
        let rows = HyperlitePullRequestPresentation.rows(scan: scan)
        rowCount = rows.count
        sections = HyperlitePullRequestSectionPlan.sections(scan: scan, rows: rows)
        visibleSections = HyperliteOpenPRProjectFilter.visibleSections(sections, hideIdle: hideIdle, now: now)
        hiddenSections = HyperliteOpenPRProjectFilter.hiddenSections(sections, hideIdle: hideIdle, now: now)
        hiddenAttentionCount = HyperliteOpenPRProjectFilter.attentionCount(hiddenSections, now: now)
        undeployed = HyperliteUndeployedPresentation.projects(sections)
    }

    var hiddenCount: Int { sections.count - visibleSections.count }

    /// Visible sections grouped by GitHub organization. Organizations keep
    /// the order of their first visible project, so the org with the most
    /// recently updated pull request leads; project order within an org is
    /// unchanged.
    /// Visible projects with open pull requests, grouped by organization.
    /// Every organization's open work comes before any idle project.
    var organizations: [HyperliteOrganizationGroup] {
        HyperliteOrganizationGroup.groups(visibleSections.filter { !$0.rows.isEmpty })
    }

    /// Visible projects without open pull requests (shown only when hide-idle
    /// is off), grouped by organization below all open work.
    var idleOrganizations: [HyperliteOrganizationGroup] {
        HyperliteOrganizationGroup.groups(visibleSections.filter(\.rows.isEmpty))
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

    /// Expanded projects first, then collapsed ones, each keeping its order.
    func sectionsOrdered(collapsed: Set<String>) -> [HyperliteProjectSection] {
        sections.filter { !collapsed.contains($0.id) } + sections.filter { collapsed.contains($0.id) }
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

/// One entry in the Open PRs list. The whole list renders from a single
/// ForEach over these, so every project section has exactly one identity and
/// moving between the open and idle tiers is a reorder. Separate ForEach
/// structures sharing explicit ids let the lazy list reuse a stale heading.
enum HyperlitePanelListItem: Identifiable, Equatable {
    case undeployedHeading([HyperliteUndeployedProject])
    case undeployedProject(HyperliteUndeployedProject)
    case undeployedRow(HyperliteUndeployedProject, HyperliteUndeployedPullRequest)
    case organization(HyperliteOrganizationGroup, idle: Bool)
    case idleDivider(count: Int)
    case section(HyperliteProjectSection, idle: Bool)

    var id: String {
        switch self {
        case .undeployedHeading: HyperliteUndeployedPresentation.bandID
        case let .undeployedProject(project): project.id
        case let .undeployedRow(project, pullRequest): project.rowID(pullRequest)
        case let .organization(group, idle): "\(idle ? "idle-" : "")\(group.id)"
        case .idleDivider: "idle-divider"
        case let .section(section, _): "section:\(section.id)"
        }
    }

    static func items(model: HyperlitePullRequestPanelModel, collapsed: Set<String>) -> [HyperlitePanelListItem] {
        var items: [HyperlitePanelListItem] = []
        if !model.undeployed.isEmpty {
            items.append(.undeployedHeading(model.undeployed))
            if !collapsed.contains(HyperliteUndeployedPresentation.bandID) {
                // Expanded projects first, then collapsed ones, as in each organization.
                let ordered = model.undeployed.filter { !collapsed.contains($0.id) }
                    + model.undeployed.filter { collapsed.contains($0.id) }
                for project in ordered {
                    items.append(.undeployedProject(project))
                    if !collapsed.contains(project.id) {
                        items += project.pullRequests.map { .undeployedRow(project, $0) }
                    }
                }
            }
        }
        for group in model.organizations {
            items.append(.organization(group, idle: false))
            items += group.sectionsOrdered(collapsed: collapsed).map { .section($0, idle: false) }
        }
        let idle = model.idleOrganizations
        if !idle.isEmpty {
            items.append(.idleDivider(count: idle.reduce(0) { $0 + $1.sections.count }))
            for group in idle {
                items.append(.organization(group, idle: true))
                items += group.sections.map { .section($0, idle: true) }
            }
        }
        return items
    }
}
