import SwiftUI

struct HyperlitePaletteColorToken: Equatable {
    let hex: UInt32

    init(_ hex: UInt32) {
        self.hex = hex
    }

    var color: Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

enum HyperlitePaletteTheme {
    // Selene Selenized Dark workbench palette:
    // github.com/santoso-wijaya/vscode-helios-selene/blob/main/themes/Selenized_Dark-color-theme.json
    static let canvas = HyperlitePaletteColorToken(0x053d48)
    static let surface = HyperlitePaletteColorToken(0x0e4956)
    static let elevatedSurface = HyperlitePaletteColorToken(0x275b69)
    static let mutedText = HyperlitePaletteColorToken(0x718b90)
    static let secondaryText = HyperlitePaletteColorToken(0xadbcbc)
    static let primaryText = HyperlitePaletteColorToken(0xc8d7d8)
    static let cyan = HyperlitePaletteColorToken(0x39c7b9)
    static let blue = HyperlitePaletteColorToken(0x0096f5)
}

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
