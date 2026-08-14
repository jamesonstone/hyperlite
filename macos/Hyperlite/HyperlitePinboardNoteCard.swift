import SwiftUI

struct HyperlitePinboardNoteCard: View {
    let note: HyperlitePinboardNote
    let layout: HyperlitePinboardNoteLayout
    let onEdit: () -> Void
    let onFork: () -> Void
    let onArchive: () -> Void
    let onMove: (Double, Double) async -> Bool

    @State private var translation = CGSize.zero
    @State private var movePending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(note.title)
                    .font(HyperliteTypography.semibold(12))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .padding(3)
                    .contentShape(Rectangle())
                    .help("Move note")
                    .gesture(dragGesture)
                    .accessibilityLabel("Move note")
            }
            Text(note.description.isEmpty ? "No description" : note.description)
                .font(HyperliteTypography.regular(10))
                .foregroundStyle(
                    note.description.isEmpty
                        ? HyperliteTheme.mutedText.color
                        : HyperliteTheme.secondaryText.color
                )
                .lineLimit(5)
            Spacer(minLength: 2)
            Text(note.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(HyperliteTypography.regular(9).monospacedDigit())
                .foregroundStyle(HyperliteTheme.mutedText.color)
        }
        .padding(10)
        .frame(width: layout.frame.width, height: layout.frame.height, alignment: .topLeading)
        .background(
            HyperliteTheme.elevatedSurface.color,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(HyperliteTheme.mutedText.color.opacity(0.35), lineWidth: 1)
        }
        .position(
            x: layout.frame.x + layout.frame.width / 2 + translation.width,
            y: layout.frame.y + layout.frame.height / 2 + translation.height
        )
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Fork", action: onFork)
            Button("Delete", role: .destructive, action: onArchive)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.title), updated \(note.updatedAt.formatted())")
        .pinboardDirectionalActions(
            leftLabel: "Move left", rightLabel: "Move right",
            upLabel: "Move up", downLabel: "Move down",
            perform: nudge
        )
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Fork", onFork)
        .accessibilityAction(named: "Delete", onArchive)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { if !movePending { translation = $0.translation } }
            .onEnded { value in commitMove(value.translation.width, value.translation.height) }
    }

    private func nudge(_ direction: MoveCommandDirection) {
        let delta = direction.pinboardDelta
        commitMove(delta.width, delta.height)
    }

    private func commitMove(_ x: Double, _ y: Double) {
        guard !movePending else { return }
        translation = CGSize(width: x, height: y)
        movePending = true
        Task {
            _ = await onMove(x, y)
            translation = .zero
            movePending = false
        }
    }
}
