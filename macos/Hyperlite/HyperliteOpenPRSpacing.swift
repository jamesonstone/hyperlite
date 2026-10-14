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

    /// Padding above and below a project heading, so headings separate from
    /// the rows around them.
    static let headingVerticalPadding: CGFloat = 6
    /// Gap between a heading's title line and its pipeline-status subheader.
    static let headingSubheaderSpacing: CGFloat = 3
    /// Gap between the deploy badge, the pipeline alerts, and the chip strip.
    static let headingGroupSpacing: CGFloat = 12
    /// Gap between workflow chips, wide enough that undotted chip names such
    /// as `deploy-nonprod deploy` read as separate items.
    static let chipSpacing: CGFloat = 14
    /// Gap between a chip's status dot and its name.
    static let chipDotSpacing: CGFloat = 4
}
