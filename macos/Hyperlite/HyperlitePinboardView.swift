import SwiftUI

struct HyperlitePinboardView: View {
    @ObservedObject var state: HyperlitePinboardState

    @State private var selectedSectionID: String?
    @State private var noteEditor: HyperlitePinboardNoteEditorContext?
    @State private var sectionEditor: HyperlitePinboardSectionEditorContext?
    @State private var sectionToDelete: HyperlitePinboardSection?
    @State private var archivePresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(HyperliteTypography.regular(11))
                    .foregroundStyle(HyperliteTheme.red.color)
            }
            content
        }
        .onReceive(state.$commandRequest) { request in
            guard let request else { return }
            handle(request.command)
            state.consumeRequest(request.id)
        }
        .sheet(item: $noteEditor) { context in noteEditorSheet(context) }
        .sheet(item: $sectionEditor) { context in sectionEditorSheet(context) }
        .sheet(isPresented: $archivePresented) { archiveSheet }
        .confirmationDialog(
            sectionDeletionTitle,
            isPresented: sectionDeletionPresented,
            titleVisibility: .visible
        ) {
            if let section = sectionToDelete {
                let count = noteCount(in: section.id)
                if count == 0 {
                    Button("Delete Section", role: .destructive) { deleteSection(section, archive: false) }
                } else {
                    Button("Archive Notes and Delete Section", role: .destructive) {
                        deleteSection(section, archive: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) { sectionToDelete = nil }
        } message: {
            Text(sectionDeletionMessage)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Pinboard")
                .font(HyperliteTypography.bold(13))
            if let snapshot = state.snapshot {
                Text("\(snapshot.notes.count) note\(snapshot.notes.count == 1 ? "" : "s")")
                    .font(HyperliteTypography.regular(10).monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
            }
            Spacer()
            Button { beginAddNote() } label: { Label("Add Note", systemImage: "note.text.badge.plus") }
                .buttonStyle(.bordered)
                .disabled(state.isMutating)
                .help("Add Pinboard note")
            Button { addSection() } label: { Label("Add Section", systemImage: "rectangle.badge.plus") }
                .buttonStyle(.bordered)
                .disabled(state.isMutating)
                .help("Add Pinboard section")
            Button { archivePresented = true } label: { Label("Archive", systemImage: "archivebox") }
                .buttonStyle(.bordered)
                .disabled(state.isMutating)
                .help("Open Pinboard archive")
        }
        .controlSize(.small)
    }

    @ViewBuilder private var content: some View {
        if state.isLoading, state.snapshot == nil {
            ProgressView("Loading Pinboard…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot = state.snapshot {
            if snapshot.board.sections.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 30))
                        .foregroundStyle(HyperliteTheme.mutedText.color)
                    Text("Create a section to begin arranging private notes.")
                        .font(HyperliteTypography.regular(12))
                        .foregroundStyle(HyperliteTheme.secondaryText.color)
                    Button("Add Section", action: addSection)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HyperlitePinboardCanvas(
                    snapshot: snapshot,
                    selectedSectionID: selectedSectionID,
                    onSelectSection: { selectedSectionID = $0 },
                    onAddNote: beginAddNote,
                    onEditNote: { note in
                        let sectionID = snapshot.board.notes.first { $0.noteID == note.id }?.sectionID
                        noteEditor = HyperlitePinboardNoteEditorContext(note: note, initialSectionID: sectionID)
                    },
                    onForkNote: forkNote,
                    onArchiveNote: archiveNote,
                    onRenameSection: beginRename,
                    onDeleteSection: { sectionToDelete = $0 },
                    onMoveSection: moveSection,
                    onMoveNote: moveNote
                )
            }
        } else {
            VStack(spacing: 10) {
                Text("Pinboard unavailable")
                    .font(HyperliteTypography.semibold(13))
                Button("Retry") { Task { await state.load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func beginAddNote(sectionID: String? = nil) {
        let sections = state.snapshot?.board.sections ?? []
        let preferred = sectionID ?? selectedSectionID ?? (sections.count == 1 ? sections[0].id : nil)
        noteEditor = HyperlitePinboardNoteEditorContext(note: nil, initialSectionID: preferred)
    }

    private func addSection() {
        Task {
            let prior = Set(state.snapshot?.board.sections.map(\.id) ?? [])
            guard let updated = await state.apply(HyperlitePinboardMutation(
                kind: .addSection,
                title: "New Section"
            )), let section = updated.board.sections.first(where: { !prior.contains($0.id) })
            else { return }
            selectedSectionID = section.id
            sectionEditor = HyperlitePinboardSectionEditorContext(id: section.id, title: section.title)
        }
    }

    private func beginRename(_ section: HyperlitePinboardSection) {
        selectedSectionID = section.id
        sectionEditor = HyperlitePinboardSectionEditorContext(id: section.id, title: section.title)
    }

    private func forkNote(_ noteID: String) {
        Task { await state.apply(HyperlitePinboardMutation(kind: .forkNote, noteID: noteID)) }
    }

    private func archiveNote(_ noteID: String) {
        Task { await state.apply(HyperlitePinboardMutation(kind: .archiveNote, noteID: noteID)) }
    }

    private func moveSection(_ sectionID: String, _ frame: HyperlitePinboardFrame) async -> Bool {
        await state.apply(HyperlitePinboardMutation(
            kind: .updateSectionFrame,
            sectionID: sectionID,
            frame: frame
        )) != nil
    }

    private func moveNote(_ noteID: String, _ sectionID: String, _ frame: HyperlitePinboardFrame) async -> Bool {
        let updated = await state.apply(HyperlitePinboardMutation(
            kind: .moveNote,
            sectionID: sectionID,
            noteID: noteID,
            frame: frame
        ))
        if updated != nil {
            selectedSectionID = sectionID
            return true
        }
        return false
    }

    private func deleteSection(_ section: HyperlitePinboardSection, archive: Bool) {
        sectionToDelete = nil
        Task {
            let updated = await state.apply(HyperlitePinboardMutation(
                kind: .deleteSection,
                sectionID: section.id,
                archiveNotes: archive
            ))
            if updated != nil, selectedSectionID == section.id { selectedSectionID = nil }
        }
    }

    private func noteCount(in sectionID: String) -> Int {
        state.snapshot?.board.notes.filter { $0.sectionID == sectionID }.count ?? 0
    }

    private var sectionDeletionPresented: Binding<Bool> {
        Binding(get: { sectionToDelete != nil }, set: { if !$0 { sectionToDelete = nil } })
    }

    private var sectionDeletionTitle: String {
        noteCount(in: sectionToDelete?.id ?? "") == 0 ? "Delete empty section?" : "Archive notes and delete section?"
    }

    private var sectionDeletionMessage: String {
        let count = noteCount(in: sectionToDelete?.id ?? "")
        if count == 0 { return "The empty section will be removed from the private Pinboard." }
        return "This section contains \(count) note\(count == 1 ? "" : "s"). They must be archived before the section can be deleted."
    }

    private func handle(_ command: HyperlitePinboardCommand) {
        switch command {
        case .addNote: beginAddNote()
        case .addSection: addSection()
        case .openArchive: archivePresented = true
        }
    }

    private func noteEditorSheet(_ context: HyperlitePinboardNoteEditorContext) -> some View {
        HyperlitePinboardNoteEditor(
            context: context,
            sections: state.snapshot?.board.sections ?? [],
            onSave: { sectionID, title, description in
                noteEditor = nil
                let kind: HyperlitePinboardMutationKind = context.note == nil ? .addNote : .updateNote
                Task {
                    await state.apply(HyperlitePinboardMutation(
                        kind: kind,
                        sectionID: sectionID,
                        noteID: context.note?.id,
                        title: title,
                        description: description
                    ))
                }
            },
            onCancel: { noteEditor = nil }
        )
    }

    private func sectionEditorSheet(_ context: HyperlitePinboardSectionEditorContext) -> some View {
        HyperlitePinboardSectionEditor(
            context: context,
            onSave: { title in
                sectionEditor = nil
                Task {
                    await state.apply(HyperlitePinboardMutation(
                        kind: .renameSection,
                        sectionID: context.id,
                        title: title
                    ))
                }
            },
            onCancel: { sectionEditor = nil }
        )
    }

    private var archiveSheet: some View {
        HyperlitePinboardArchiveView(
            notes: state.snapshot?.archive ?? [],
            sections: state.snapshot?.board.sections ?? [],
            onRestore: { note, sectionID in
                Task {
                    await state.apply(HyperlitePinboardMutation(
                        kind: .restoreNote,
                        sectionID: sectionID,
                        noteID: note.id
                    ))
                }
            },
            onClose: { archivePresented = false }
        )
    }
}
