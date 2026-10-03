import SwiftUI

/// Scrollable container for the Open PRs list.
struct HyperliteOpenPRWatchColumn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
