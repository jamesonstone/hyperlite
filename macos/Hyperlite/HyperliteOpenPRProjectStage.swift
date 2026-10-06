import SwiftUI

enum HyperliteOpenPRProjectStageKind: Equatable {
    case active
    case notable
    case alert
    case idle

    static func forSection(
        _ section: HyperliteProjectSection,
        chips: [HyperliteWorkflowChip],
        alerts: [HyperlitePipelineAlert] = [],
        undeployed: Bool = false
    ) -> HyperliteOpenPRProjectStageKind {
        if chips.contains(where: \.isRunning) { return .notable }
        if !alerts.isEmpty || undeployed { return .alert }
        switch HyperliteProjectSectionChrome.headingWeight(
            idle: section.rows.isEmpty,
            chips: chips,
            alerts: alerts
        ) {
        case .active: return .active
        case .notable: return .notable
        case .idle: return .idle
        }
    }

    var lanternIsLive: Bool { self == .notable || self == .alert }
    var lanternUsesAttentionColor: Bool { self == .alert }

    var lanternOpacity: Double {
        switch self {
        case .notable, .alert: 0.92
        case .active: 0.28
        case .idle: 0.10
        }
    }
}

/// Presentation helpers for a collapsible Open PRs project section, kept free
/// of the view's generic row type so they stay unit-testable.
enum HyperliteOpenPRProjectSectionPresentation {
    /// Only projects that actually have open pull-request rows can collapse;
    /// an idle project heading has nothing to hide.
    static func canCollapse(_ section: HyperliteProjectSection) -> Bool {
        !section.rows.isEmpty
    }

    static func storageKey(projectID: String) -> String {
        "hyperlite.openpr.collapsed.\(projectID)"
    }
}
