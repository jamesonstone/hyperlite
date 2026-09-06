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

struct HyperliteColorPalette: Equatable {
    let colorScheme: ColorScheme
    let canvas: HyperliteColorToken
    let surface: HyperliteColorToken
    let elevatedSurface: HyperliteColorToken
    let mutedText: HyperliteColorToken
    let secondaryText: HyperliteColorToken
    let primaryText: HyperliteColorToken
    let red: HyperliteColorToken
    let orange: HyperliteColorToken
    let green: HyperliteColorToken
    let cyan: HyperliteColorToken
    let blue: HyperliteColorToken
}

enum HyperliteTheme {
    static var canvas: HyperliteColorToken { current.canvas }
    static var surface: HyperliteColorToken { current.surface }
    static var elevatedSurface: HyperliteColorToken { current.elevatedSurface }
    static var mutedText: HyperliteColorToken { current.mutedText }
    static var secondaryText: HyperliteColorToken { current.secondaryText }
    static var primaryText: HyperliteColorToken { current.primaryText }
    static var red: HyperliteColorToken { current.red }
    static var orange: HyperliteColorToken { current.orange }
    static var green: HyperliteColorToken { current.green }
    static var cyan: HyperliteColorToken { current.cyan }
    static var blue: HyperliteColorToken { current.blue }
    static var colorScheme: ColorScheme { current.colorScheme }

    static var current: HyperliteColorPalette {
        HyperliteAppearance.shared.palette
    }
}

private struct HyperliteThemeModifier: ViewModifier {
    @ObservedObject var appearance = HyperliteAppearance.shared

    func body(content: Content) -> some View {
        content
            .foregroundStyle(appearance.palette.primaryText.color)
            .tint(appearance.palette.blue.color)
            .background(appearance.palette.canvas.color)
            .environment(\.colorScheme, appearance.palette.colorScheme)
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
