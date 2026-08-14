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
    let onMoveSection: (String, HyperlitePinboardFrame) -> Void
    let onMoveNote: (String, String, HyperlitePinboardFrame) -> Void

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
                        onMoveSection: { frame in onMoveSection(section.id, frame) },
                        onMoveNote: { layout, x, y in
                            guard let destination = HyperlitePinboardGeometry.noteDestination(
                                layout: layout,
                                translationX: x,
                                translationY: y,
                                sections: snapshot.board.sections
                            ) else { return }
                            onMoveNote(
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
    let onMoveSection: (HyperlitePinboardFrame) -> Void
    let onMoveNote: (HyperlitePinboardNoteLayout, Double, Double) -> Void

    @State private var moveTranslation = CGSize.zero
    @State private var resizeTranslation = CGSize.zero

    private var displayedFrame: HyperlitePinboardFrame {
        let moved = HyperlitePinboardGeometry.movedSection(
            section.frame,
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
                            onMove: { x, y in onMoveNote(layout, x, y) }
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
        }
        .padding(.horizontal, 10)
        .background(HyperliteTheme.elevatedSurface.color.opacity(0.82))
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { moveTranslation = $0.translation }
            .onEnded { value in
                let frame = HyperlitePinboardGeometry.movedSection(
                    section.frame,
                    translationX: value.translation.width,
                    translationY: value.translation.height,
                    board: board.size
                )
                moveTranslation = .zero
                onMoveSection(frame)
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
                    .onChanged { resizeTranslation = $0.translation }
                    .onEnded { value in
                        let frame = HyperlitePinboardGeometry.resizedSection(
                            section.frame,
                            translationX: value.translation.width,
                            translationY: value.translation.height,
                            board: board.size
                        )
                        resizeTranslation = .zero
                        onMoveSection(frame)
                    }
            )
            .accessibilityLabel("Resize section")
    }
}

private struct HyperlitePinboardNoteCard: View {
    let note: HyperlitePinboardNote
    let layout: HyperlitePinboardNoteLayout
    let onEdit: () -> Void
    let onFork: () -> Void
    let onArchive: () -> Void
    let onMove: (Double, Double) -> Void

    @State private var translation = CGSize.zero

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
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Fork", onFork)
        .accessibilityAction(named: "Delete", onArchive)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { translation = $0.translation }
            .onEnded { value in
                translation = .zero
                onMove(value.translation.width, value.translation.height)
            }
    }
}
