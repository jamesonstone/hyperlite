import SwiftUI

struct HyperliteGhostMark: View {
    var body: some View {
        HyperliteGhostShape()
            .fill(.primary, style: FillStyle(eoFill: true))
            .accessibilityHidden(true)
    }
}

private struct HyperliteGhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * width, y: rect.minY + y * height)
        }

        var path = Path()
        path.move(to: point(0.12, 0.84))
        path.addLine(to: point(0.12, 0.37))
        path.addCurve(
            to: point(0.50, 0.08),
            control1: point(0.12, 0.19),
            control2: point(0.29, 0.08)
        )
        path.addCurve(
            to: point(0.88, 0.37),
            control1: point(0.71, 0.08),
            control2: point(0.88, 0.19)
        )
        path.addLine(to: point(0.88, 0.84))
        path.addCurve(
            to: point(0.74, 0.91),
            control1: point(0.88, 0.91),
            control2: point(0.82, 0.95)
        )
        path.addCurve(
            to: point(0.50, 0.86),
            control1: point(0.65, 0.84),
            control2: point(0.58, 0.82)
        )
        path.addCurve(
            to: point(0.26, 0.91),
            control1: point(0.42, 0.82),
            control2: point(0.35, 0.84)
        )
        path.addCurve(
            to: point(0.12, 0.84),
            control1: point(0.18, 0.95),
            control2: point(0.12, 0.91)
        )
        path.closeSubpath()

        path.addEllipse(in: CGRect(
            x: rect.minX + 0.28 * width,
            y: rect.minY + 0.34 * height,
            width: 0.16 * width,
            height: 0.18 * height
        ))
        path.addEllipse(in: CGRect(
            x: rect.minX + 0.56 * width,
            y: rect.minY + 0.34 * height,
            width: 0.16 * width,
            height: 0.18 * height
        ))
        path.addRoundedRect(
            in: CGRect(
                x: rect.minX + 0.42 * width,
                y: rect.minY + 0.62 * height,
                width: 0.16 * width,
                height: 0.06 * height
            ),
            cornerSize: CGSize(width: 0.03 * width, height: 0.03 * height)
        )
        return path
    }
}
