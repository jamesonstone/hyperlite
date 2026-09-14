import SwiftUI

enum HyperliteHiddenProjectListPresentation {
    static let caption = "watching the quiet ones"
    static let expandedStorageKey = "hyperlite.openpr.quiet-ones.expanded"

    static func accessibilityLabel(count: Int, attentionCount: Int = 0) -> String {
        var label = "\(caption), \(count) idle project\(count == 1 ? "" : "s")"
        if attentionCount > 0 {
            label += ", \(attentionCount) need\(attentionCount == 1 ? "s" : "") attention"
        }
        return label
    }
}

/// A standard collapsible list for the projects hidden by the hide-idle eye —
/// every project without an open pull request. It doubles as a project
/// launcher, so its expanded state persists across launches and each row opens
/// the project's repository. Expanding shows each project's heading with its
/// workflow chips and pipeline-alert badges, so a failure stays one expand
/// away. `DisclosureGroup` gives native keyboard activation and VoiceOver.
struct HyperliteHiddenProjectList<Content: View>: View {
    let count: Int
    var attentionCount: Int = 0
    var selected = false
    @ViewBuilder var content: Content
    @AppStorage(HyperliteHiddenProjectListPresentation.expandedStorageKey)
    private var expanded = false

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
        .accessibilityLabel(HyperliteHiddenProjectListPresentation.accessibilityLabel(
            count: count, attentionCount: attentionCount
        ))
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(HyperliteHiddenProjectListPresentation.caption)
                .font(HyperliteTypography.compact)
                .foregroundStyle(HyperliteTheme.mutedText.color)
            Text("\(count)")
                .font(HyperliteTypography.compact.monospacedDigit())
                .foregroundStyle(HyperliteTheme.mutedText.color)
            if attentionCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(HyperliteTheme.red.color)
                        .frame(width: 5, height: 5)
                    Text("\(attentionCount)")
                        .font(HyperliteTypography.compact.monospacedDigit())
                        .foregroundStyle(HyperliteTheme.orange.color)
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .hyperliteNavHighlight(selected: selected)
    }
}
