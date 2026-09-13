import SwiftUI

struct HyperliteProjectCelestialIcon: View {
    let kind: HyperliteProjectCelestialKind
    var id: String = ""
    var diameter: CGFloat? = nil
    var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    private var size: CGFloat { diameter ?? kind.listDiameter }

    var body: some View {
        Text(kind.emoji(for: id))
            .font(.system(size: size * 0.86))
            .frame(width: size, height: size)
            .rotationEffect(spinning && spin && !reduceMotion ? .degrees(360) : .zero)
            .onAppear { spinning = true }
            .animation(
                spin && !reduceMotion
                    ? .linear(duration: kind.spinPeriod).repeatForever(autoreverses: false)
                    : nil,
                value: spinning
            )
            .accessibilityHidden(true)
    }
}
