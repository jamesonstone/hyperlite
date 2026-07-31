import AppKit
import SwiftUI

struct HyperliteColorToken: Equatable {
    let hex: UInt32

    init(_ hex: UInt32) {
        self.hex = hex
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var appKitColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    private var red: Double { Double((hex >> 16) & 0xff) / 255 }
    private var green: Double { Double((hex >> 8) & 0xff) / 255 }
    private var blue: Double { Double(hex & 0xff) / 255 }
}

enum HyperliteTheme {
    // Selene Selenized Dark workbench palette:
    // github.com/santoso-wijaya/vscode-helios-selene/blob/main/themes/Selenized_Dark-color-theme.json
    static let canvas = HyperliteColorToken(0x053d48)
    static let surface = HyperliteColorToken(0x0e4956)
    static let elevatedSurface = HyperliteColorToken(0x275b69)
    static let mutedText = HyperliteColorToken(0x718b90)
    static let secondaryText = HyperliteColorToken(0xadbcbc)
    static let primaryText = HyperliteColorToken(0xc8d7d8)
    static let red = HyperliteColorToken(0xfd564e)
    static let orange = HyperliteColorToken(0xf38649)
    static let green = HyperliteColorToken(0x80b83c)
    static let cyan = HyperliteColorToken(0x39c7b9)
    static let blue = HyperliteColorToken(0x0096f5)
}

private struct HyperliteThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(HyperliteTheme.primaryText.color)
            .tint(HyperliteTheme.blue.color)
            .background(HyperliteTheme.canvas.color)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func hyperliteTheme() -> some View {
        modifier(HyperliteThemeModifier())
    }
}

struct HyperliteThemeDivider: View {
    var body: some View {
        Rectangle()
            .fill(HyperliteTheme.elevatedSurface.color)
            .frame(height: 1)
    }
}
