import SwiftUI

/// Scrollable container for the Open PRs list. The system scroller is hidden:
/// it drew a bright, always-on bar beside the list, and keyboard navigation
/// (j/k, arrows) plus trackpad and wheel scrolling all keep working.
struct HyperliteOpenPRWatchColumn<Content: View>: View {
    var scrollRequest: HyperliteScrollRequest?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onChange(of: scrollRequest) { request in
                guard let request else { return }
                scroll(proxy, to: request)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Sections are lazy, so a distant row may not exist yet: bring its
    /// section on screen first, then the row itself on the next pass.
    private func scroll(_ proxy: ScrollViewProxy, to request: HyperliteScrollRequest) {
        let anchor: UnitPoint? = request.centered ? .center : nil
        if let sectionID = HyperlitePullRequestJump.sectionID(for: request.id),
           request.centered || request.id.hasPrefix(HyperliteWorkspaceNavigation.headerID(sectionID: ""))
        {
            proxy.scrollTo(sectionID, anchor: request.centered ? .top : nil)
        }
        DispatchQueue.main.async {
            proxy.scrollTo(request.id, anchor: anchor)
        }
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
