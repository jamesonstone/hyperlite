import SwiftUI

struct HyperliteProjectCelestialIcon: View {
    let kind: HyperliteProjectCelestialKind
    var diameter: CGFloat? = nil

    private var size: CGFloat { diameter ?? kind.listDiameter }

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: size * 0.72))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .overlay {
                if kind == .planet || kind == .giant {
                    Circle()
                        .stroke(tint.opacity(0.55), lineWidth: 1)
                        .frame(width: size, height: size)
                }
            }
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch kind {
        case .star: HyperliteTheme.mutedText.color
        case .moon: HyperliteTheme.secondaryText.color
        case .planet: HyperliteTheme.cyan.color
        case .giant: HyperliteTheme.orange.color
        }
    }
}
