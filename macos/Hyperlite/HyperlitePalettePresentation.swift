import SwiftUI

enum HyperlitePaletteLayout {
    static let maximumWidth: CGFloat = 560
    static let maximumHeight: CGFloat = 480
    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 48

    static func size(containerWidth: CGFloat, containerHeight: CGFloat) -> CGSize {
        CGSize(
            width: min(maximumWidth, max(0, containerWidth - (horizontalInset * 2))),
            height: min(maximumHeight, max(0, containerHeight - (verticalInset * 2)))
        )
    }
}
