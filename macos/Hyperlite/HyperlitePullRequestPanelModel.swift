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
