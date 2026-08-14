import SwiftUI

extension MoveCommandDirection {
    var pinboardDelta: CGSize {
        switch self {
        case .left: CGSize(width: -20, height: 0)
        case .right: CGSize(width: 20, height: 0)
        case .up: CGSize(width: 0, height: -20)
        case .down: CGSize(width: 0, height: 20)
        @unknown default: .zero
        }
    }
}

private struct HyperlitePinboardDirectionalActions: ViewModifier {
    let leftLabel: String
    let rightLabel: String
    let upLabel: String
    let downLabel: String
    let perform: (MoveCommandDirection) -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .onMoveCommand(perform: perform)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Use the arrow keys to adjust")
            .accessibilityAction(named: leftLabel) { perform(.left) }
            .accessibilityAction(named: rightLabel) { perform(.right) }
            .accessibilityAction(named: upLabel) { perform(.up) }
            .accessibilityAction(named: downLabel) { perform(.down) }
    }
}

extension View {
    func pinboardDirectionalActions(
        leftLabel: String,
        rightLabel: String,
        upLabel: String,
        downLabel: String,
        perform: @escaping (MoveCommandDirection) -> Void
    ) -> some View {
        modifier(HyperlitePinboardDirectionalActions(
            leftLabel: leftLabel,
            rightLabel: rightLabel,
            upLabel: upLabel,
            downLabel: downLabel,
            perform: perform
        ))
    }
}
