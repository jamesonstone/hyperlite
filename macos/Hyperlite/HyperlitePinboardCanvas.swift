import SwiftUI

struct HyperlitePinboardCanvas: View {
    let snapshot: HyperlitePinboardSnapshot
    let selectedSectionID: String?
    let onSelectSection: (String) -> Void
    let onAddNote: (String) -> Void
    let onEditNote: (HyperlitePinboardNote) -> Void
    let onForkNote: (String) -> Void
    let onArchiveNote: (String) -> Void
    let onRenameSection: (HyperlitePinboardSection) -> Void
    let onDeleteSection: (HyperlitePinboardSection) -> Void
    let onMoveSection: (String, HyperlitePinboardFrame) async -> Bool
    let onMoveNote: (String, String, HyperlitePinboardFrame) async -> Bool

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                HyperliteTheme.canvas.color
                ForEach(snapshot.board.sections) { section in
                    HyperlitePinboardSectionRegion(
                        section: section,
                        board: snapshot.board,
                        notes: snapshot.notesByID,
                        selected: selectedSectionID == section.id,
                        onSelect: { onSelectSection(section.id) },
                        onAddNote: { onAddNote(section.id) },
                        onEditNote: onEditNote,
                        onForkNote: onForkNote,
                        onArchiveNote: onArchiveNote,
                        onRename: { onRenameSection(section) },
                        onDelete: { onDeleteSection(section) },
                        onMoveSection: { frame in await onMoveSection(section.id, frame) },
                        onMoveNote: { layout, x, y in
                            guard let destination = HyperlitePinboardGeometry.noteDestination(
                                layout: layout,
                                translationX: x,
                                translationY: y,
                                sections: snapshot.board.sections
                            ) else { return false }
                            return await onMoveNote(
                                destination.noteID,
                                destination.sectionID,
                                destination.frame
                            )
                        }
                    )
                }
            }
            .frame(width: snapshot.board.size.width, height: snapshot.board.size.height)
            .background(HyperliteTheme.canvas.color)
        }
        .background(HyperliteTheme.canvas.color)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(HyperliteTheme.elevatedSurface.color, lineWidth: 1)
        }
    }
}

private struct HyperlitePinboardSectionRegion: View {
    let section: HyperlitePinboardSection
    let board: HyperlitePinboardBoard
    let notes: [String: HyperlitePinboardNote]
    let selected: Bool
    let onSelect: () -> Void
    let onAddNote: () -> Void
    let onEditNote: (HyperlitePinboardNote) -> Void
    let onForkNote: (String) -> Void
    let onArchiveNote: (String) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onMoveSection: (HyperlitePinboardFrame) async -> Bool
    let onMoveNote: (HyperlitePinboardNoteLayout, Double, Double) async -> Bool

    @State private var moveTranslation = CGSize.zero
    @State private var resizeTranslation = CGSize.zero
    @State private var pendingFrame: HyperlitePinboardFrame?

    private var displayedFrame: HyperlitePinboardFrame {
        let moved = HyperlitePinboardGeometry.movedSection(
            pendingFrame ?? section.frame,
            translationX: moveTranslation.width,
            translationY: moveTranslation.height,
            board: board.size
        )
        return HyperlitePinboardGeometry.resizedSection(
            moved,
            translationX: resizeTranslation.width,
            translationY: resizeTranslation.height,
            board: board.size
        )
    }

    private var layouts: [HyperlitePinboardNoteLayout] {
        board.notes.filter { $0.sectionID == section.id }
    }

    var body: some View {
        let frame = displayedFrame
        VStack(spacing: 0) {
            sectionHeader
                .frame(height: HyperlitePinboardGeometry.sectionHeaderHeight)
            ZStack(alignment: .topLeading) {
                HyperliteTheme.surface.color.opacity(0.56)
                ForEach(layouts) { layout in
                    if let note = notes[layout.noteID] {
                        HyperlitePinboardNoteCard(
                            note: note,
                            layout: layout,
                            onEdit: { onEditNote(note) },
                            onFork: { onForkNote(note.id) },
                            onArchive: { onArchiveNote(note.id) },
                            onMove: { x, y in await onMoveNote(layout, x, y) }
                        )
                    }
                }
            }
            .frame(width: frame.width, height: frame.height - HyperlitePinboardGeometry.sectionHeaderHeight)
            .clipped()
        }
        .frame(width: frame.width, height: frame.height)
        .background(HyperliteTheme.surface.color.opacity(0.8))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    selected ? HyperliteTheme.cyan.color : HyperliteTheme.elevatedSurface.color,
                    lineWidth: selected ? 2 : 1
                )
        }
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .position(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Rename Section", action: onRename)
            Button("Add Note", action: onAddNote)
            Divider()
            Button("Delete Section", role: .destructive, action: onDelete)
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Button(action: onRename) {
                Text(section.title)
                    .font(HyperliteTypography.semibold(12))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Rename section")
            Button(action: onAddNote) { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .help("Add note to \(section.title)")
            Image(systemName: "move.3d")
                .font(HyperliteTypography.semibold(11))
                .foregroundStyle(HyperliteTheme.mutedText.color)
                .padding(5)
                .contentShape(Rectangle())
                .help("Move section")
                .gesture(moveGesture)
                .accessibilityLabel("Move section")
                .pinboardDirectionalActions(
                    leftLabel: "Move left", rightLabel: "Move right",
                    upLabel: "Move up", downLabel: "Move down",
                    perform: nudgeSection
                )
        }
        .padding(.horizontal, 10)
        .background(HyperliteTheme.elevatedSurface.color.opacity(0.82))
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { if pendingFrame == nil { moveTranslation = $0.translation } }
            .onEnded { value in
                defer { moveTranslation = .zero }
                guard pendingFrame == nil else { return }
                let frame = HyperlitePinboardGeometry.movedSection(
                    section.frame,
                    translationX: value.translation.width,
                    translationY: value.translation.height,
                    board: board.size
                )
                commit(frame)
            }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(HyperliteTypography.regular(10))
            .foregroundStyle(HyperliteTheme.mutedText.color)
            .padding(7)
            .contentShape(Rectangle())
            .help("Resize section")
            .gesture(
                DragGesture()
                    .onChanged { if pendingFrame == nil { resizeTranslation = $0.translation } }
                    .onEnded { value in
                        defer { resizeTranslation = .zero }
                        guard pendingFrame == nil else { return }
                        let frame = HyperlitePinboardGeometry.resizedSection(
                            section.frame,
                            translationX: value.translation.width,
                            translationY: value.translation.height,
                            board: board.size
                        )
                        commit(frame)
                    }
            )
            .accessibilityLabel("Resize section")
            .pinboardDirectionalActions(
                leftLabel: "Make narrower", rightLabel: "Make wider",
                upLabel: "Make shorter", downLabel: "Make taller",
                perform: resizeSection
            )
    }

    private func nudgeSection(_ direction: MoveCommandDirection) {
        let delta = direction.pinboardDelta
        commit(HyperlitePinboardGeometry.movedSection(
            pendingFrame ?? section.frame,
            translationX: delta.width,
            translationY: delta.height,
            board: board.size
        ))
    }

    private func resizeSection(_ direction: MoveCommandDirection) {
        let delta = direction.pinboardDelta
        commit(HyperlitePinboardGeometry.resizedSection(
            pendingFrame ?? section.frame,
            translationX: delta.width,
            translationY: delta.height,
            board: board.size
        ))
    }

    private func commit(_ frame: HyperlitePinboardFrame) {
        guard pendingFrame == nil else { return }
        pendingFrame = frame
        Task {
            _ = await onMoveSection(frame)
            pendingFrame = nil
        }
    }
}
