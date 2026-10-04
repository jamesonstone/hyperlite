import CoreGraphics

/// Shared vertical rhythm for the Open PRs list.
enum HyperliteOpenPRSpacing {
    /// Even padding inside each row so the keyboard highlight centers on it.
    static let rowVerticalPadding: CGFloat = 3

    /// Every row has the same explicit height, sized from the list font, so no
    /// row content can draw outside its frame and the lazy list sizes exactly.
    static func rowHeight(bodySize: CGFloat) -> CGFloat {
        (bodySize * 1.5).rounded(.up) + 2
    }
}
