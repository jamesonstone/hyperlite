import SwiftUI

/// Scrollable container for the Open PRs list. Keeps the refresh ghost overlay
/// above the content; hidden idle projects are presented inline by the panel as
/// a collapsible list rather than a leftover animation.
struct HyperliteOpenPRWatchColumn<Content: View>: View {
    let isRefreshing: Bool
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .overlay {
            HyperliteOpenPRRefreshGhostOverlay(isRefreshing: isRefreshing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

