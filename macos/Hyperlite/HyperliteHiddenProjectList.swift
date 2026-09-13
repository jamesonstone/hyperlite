import SwiftUI

enum HyperliteHiddenProjectListPresentation {
    static let caption = "watching the quiet ones"

    static func accessibilityLabel(count: Int) -> String {
        "\(caption), \(count) idle projects"
    }
}

/// A standard collapsible list for idle projects hidden by the hide-idle eye.
/// Collapsed by default so the quiet projects stay out of the way; expanding
/// reveals each project's heading. `DisclosureGroup` gives native keyboard
/// activation and VoiceOver support.
struct HyperliteHiddenProjectList<Content: View>: View {
    let count: Int
    @ViewBuilder var content: Content
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: HyperliteWorkspaceSplit.stackedStageSpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, HyperliteWorkspaceSplit.stackedStageSpacing)
        } label: {
            label
        }
        .padding(.leading, HyperlitePullRequestRowLayout.rowChromeLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(HyperliteHiddenProjectListPresentation.accessibilityLabel(count: count))
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(HyperliteHiddenProjectListPresentation.caption)
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Text("\(count)")
                .font(HyperliteTypography.compact.monospacedDigit())
                .foregroundStyle(HyperliteTheme.mutedText.color)
        }
        .contentShape(Rectangle())
    }
}
