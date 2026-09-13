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

    var fillOpacity: Double {
        switch self {
        case .pinned, .active: 0.58
        case .notable: 0.46
        case .idle: 0.22
        }
    }

    var showsLiveStroke: Bool {
        self == .notable
    }
}

struct HyperliteOpenPRProjectStage<Content: View>: View {
    let kind: HyperliteOpenPRProjectStageKind
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: HyperliteWorkspaceSplit.stackedLazySpacing) {
            content
        }
        .padding(.vertical, HyperliteWorkspaceSplit.stackedStageVerticalPadding)
        .padding(.trailing, 4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HyperliteTheme.elevatedSurface.color.opacity(kind.fillOpacity))
                .overlay {
                    if kind.showsLiveStroke {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                HyperliteTheme.cyan.color.opacity(0.34),
                                lineWidth: 1
                            )
                    }
                }
        }
    }
}
