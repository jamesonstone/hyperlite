import SwiftUI

enum HyperliteOpenPRProjectStageKind: Equatable {
    case pinned
    case active
    case notable
    case alert
    case idle

    static func forSection(
        _ section: HyperliteProjectSection,
        chips: [HyperliteWorkflowChip],
        alerts: [HyperlitePipelineAlert] = []
    ) -> HyperliteOpenPRProjectStageKind {
        if chips.contains(where: \.isRunning) { return .notable }
        if !alerts.isEmpty { return .alert }
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
        case .pinned, .active: 0.28
        case .idle: 0.10
        }
    }
}

struct HyperliteOpenPRProjectStage<Content: View>: View {
    let kind: HyperliteOpenPRProjectStageKind
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Capsule()
                .fill(
                    kind.lanternUsesAttentionColor
                        ? HyperliteTheme.orange.color
                        : kind.lanternIsLive
                            ? HyperliteTheme.cyan.color
                            : HyperliteTheme.mutedText.color
                )
                .frame(width: 3)
                .padding(.vertical, 3)
                .opacity(kind.lanternOpacity)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HyperliteWorkspaceSplit.stackedLazySpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, HyperliteWorkspaceSplit.stackedStageVerticalPadding)
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

/// One project cluster in the Open PRs list: a lantern stage whose heading can
/// collapse the pull-request rows beneath it. Collapsed keeps the project name
/// and its open-PR count visible so the list stays scannable by project. The
/// collapsed state persists per project. Only projects with rows can collapse.
struct HyperliteOpenPRProjectSection<Rows: View>: View {
    let section: HyperliteProjectSection
    let chips: [HyperliteWorkflowChip]
    let compact: Bool
    @Binding var draggedRowID: String?
    let drop: (String) -> Void
    @ViewBuilder var rows: Rows
    @AppStorage private var collapsed: Bool

    init(
        section: HyperliteProjectSection,
        chips: [HyperliteWorkflowChip],
        compact: Bool,
        draggedRowID: Binding<String?>,
        drop: @escaping (String) -> Void,
        @ViewBuilder rows: () -> Rows
    ) {
        self.section = section
        self.chips = chips
        self.compact = compact
        self._draggedRowID = draggedRowID
        self.drop = drop
        self.rows = rows()
        self._collapsed = AppStorage(
            wrappedValue: false,
            HyperliteOpenPRProjectSectionPresentation.storageKey(projectID: section.id)
        )
    }

    private var canCollapse: Bool {
        HyperliteOpenPRProjectSectionPresentation.canCollapse(section)
    }

    var body: some View {
        HyperliteOpenPRProjectStage(
            kind: .forSection(
                section, chips: chips,
                alerts: HyperlitePipelineAlertPresentation.alerts(from: section.project.workflows)
            )
        ) {
            HyperliteProjectSectionHeader(
                section: section,
                chips: chips,
                compact: compact,
                collapsed: canCollapse ? $collapsed : nil,
                draggedRowID: $draggedRowID,
                drop: drop
            )
            if !canCollapse || !collapsed {
                rows
            }
        }
    }
}
