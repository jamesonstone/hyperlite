import SwiftUI

/// Scrollable container for the Open PRs list. The system scroller is hidden:
/// it drew a bright, always-on bar beside the list, and keyboard navigation
/// (j/k, arrows) plus trackpad and wheel scrolling all keep working.
struct HyperliteOpenPRWatchColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Shared vertical rhythm for the Open PRs list stages and headings.
enum HyperliteOpenPRSpacing {
    static let activeSectionTopPadding: CGFloat = 10
    static let idleSectionTopPadding: CGFloat = 2
    static let lazySpacing: CGFloat = 4
    static let stageVerticalPadding: CGFloat = 4
    static let stageSpacing: CGFloat = 10
}
