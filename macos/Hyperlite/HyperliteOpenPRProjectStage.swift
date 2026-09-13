import SwiftUI

enum HyperliteOpenPRProjectStageKind: Equatable {
    case pinned
    case active
    case notable
    case idle

    static func forSection(
        _ section: HyperliteProjectSection,
        chips: [HyperliteWorkflowChip]
    ) -> HyperliteOpenPRProjectStageKind {
        switch HyperliteProjectSectionChrome.headingWeight(
            idle: section.rows.isEmpty,
            chips: chips
        ) {
        case .active: .active
        case .notable: .notable
        case .idle: .idle
        }
    }

    var lanternIsLive: Bool { self == .notable }

    var lanternOpacity: Double {
        switch self {
        case .notable: 0.92
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
                    kind.lanternIsLive
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
