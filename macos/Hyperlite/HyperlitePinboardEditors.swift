import SwiftUI

struct HyperlitePinboardNoteEditorContext: Identifiable {
    let id = UUID()
    let note: HyperlitePinboardNote?
    let initialSectionID: String?
}

struct HyperlitePinboardSectionEditorContext: Identifiable {
    let id: String
    let title: String
}

struct HyperlitePinboardNoteEditor: View {
    let context: HyperlitePinboardNoteEditorContext
    let sections: [HyperlitePinboardSection]
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var description: String
    @State private var sectionID: String

    init(
        context: HyperlitePinboardNoteEditorContext,
        sections: [HyperlitePinboardSection],
        onSave: @escaping (String, String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.context = context
        self.sections = sections
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: context.note?.title ?? "")
        _description = State(initialValue: context.note?.description ?? "")
        let soleSectionID = sections.count == 1 ? sections[0].id : ""
        _sectionID = State(initialValue: context.initialSectionID ?? soleSectionID)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var saveDisabled: Bool {
        trimmedTitle.isEmpty || trimmedTitle.contains("\n") ||
            trimmedTitle.utf8.count > 256 || description.utf8.count > 256 * 1024 ||
            !sections.contains(where: { $0.id == sectionID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(context.note == nil ? "Add Pinboard Note" : "Edit Pinboard Note")
                .font(HyperliteTypography.bold(18))
            if context.note == nil, sections.count > 1 {
                Picker("Section", selection: $sectionID) {
                    Text("Choose a section").tag("")
                    ForEach(sections) { section in Text(section.title).tag(section.id) }
                }
            } else if let section = sections.first(where: { $0.id == sectionID }) {
                LabeledContent("Section", value: section.title)
            }
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(HyperliteTypography.regular(12))
            VStack(alignment: .leading, spacing: 5) {
                Text("Description")
                    .font(HyperliteTypography.medium(11))
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
                TextEditor(text: $description)
                    .font(HyperliteTypography.regular(12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        HyperliteTheme.surface.color,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(HyperliteTheme.elevatedSurface.color, lineWidth: 1)
                    }
                    .frame(minHeight: 180)
            }
            if let note = context.note {
                HStack(spacing: 18) {
                    metadata("Created", note.createdAt)
                    metadata("Updated", note.updatedAt)
                }
            }
            if sections.isEmpty {
                Label("Create a section before adding a note.", systemImage: "rectangle.badge.plus")
                    .foregroundStyle(HyperliteTheme.orange.color)
            }
            HStack {
                Text("\(description.utf8.count) / \(256 * 1024) bytes")
                    .font(HyperliteTypography.regular(9).monospacedDigit())
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(sectionID, trimmedTitle, description) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saveDisabled)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 420)
        .hyperliteTheme()
    }

    private func metadata(_ label: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(HyperliteTypography.medium(9))
            Text(date, format: .dateTime.year().month().day().hour().minute())
                .font(HyperliteTypography.regular(9).monospacedDigit())
        }
        .foregroundStyle(HyperliteTheme.mutedText.color)
    }
}

struct HyperlitePinboardSectionEditor: View {
    let context: HyperlitePinboardSectionEditorContext
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var title: String

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(
        context: HyperlitePinboardSectionEditorContext,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.context = context
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: context.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Pinboard Section")
                .font(HyperliteTypography.bold(18))
            TextField("Section title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(HyperliteTypography.regular(12))
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(trimmedTitle) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        trimmedTitle.isEmpty || trimmedTitle.contains("\n") ||
                            trimmedTitle.utf8.count > 256
                    )
            }
        }
        .padding(20)
        .frame(width: 420)
        .hyperliteTheme()
    }
}

struct HyperlitePinboardArchiveView: View {
    let notes: [HyperlitePinboardNote]
    let sections: [HyperlitePinboardSection]
    let onRestore: (HyperlitePinboardNote, String) -> Void
    let onClose: () -> Void
    @State private var destinations: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pinboard Archive").font(HyperliteTypography.bold(18))
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
            if notes.isEmpty {
                Text("No archived notes")
                    .foregroundStyle(HyperliteTheme.mutedText.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(notes) { note in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(note.title).font(HyperliteTypography.semibold(12))
                        Text(
                            "From \(note.archivedFromSectionTitle ?? "Unknown section") · " +
                                (note.archivedFromSectionID ?? "unknown id")
                        )
                            .font(HyperliteTypography.regular(10))
                            .foregroundStyle(HyperliteTheme.secondaryText.color)
                            .textSelection(.enabled)
                        HStack(spacing: 12) {
                            timestamp("Created", note.createdAt)
                            timestamp("Updated", note.updatedAt)
                            if let archivedAt = note.archivedAt { timestamp("Archived", archivedAt) }
                        }
                        HStack {
                            if destinationRequiresChoice(note) {
                                Picker("Restore to", selection: destinationBinding(note)) {
                                    Text("Choose section").tag("")
                                    ForEach(sections) { section in Text(section.title).tag(section.id) }
                                }
                                .frame(maxWidth: 260)
                            }
                            Spacer()
                            Button("Restore") {
                                onRestore(note, restoreSectionID(note))
                            }
                            .disabled(restoreSectionID(note).isEmpty)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 420)
        .hyperliteTheme()
    }

    private func destinationRequiresChoice(_ note: HyperlitePinboardNote) -> Bool {
        sections.count != 1 && !sections.contains { $0.id == note.archivedFromSectionID }
    }

    private func restoreSectionID(_ note: HyperlitePinboardNote) -> String {
        if let original = note.archivedFromSectionID,
           sections.contains(where: { $0.id == original }) { return original }
        if sections.count == 1 { return sections[0].id }
        return destinations[note.id] ?? ""
    }

    private func destinationBinding(_ note: HyperlitePinboardNote) -> Binding<String> {
        Binding(
            get: { destinations[note.id] ?? "" },
            set: { destinations[note.id] = $0 }
        )
    }

    private func timestamp(_ label: String, _ date: Date) -> some View {
        Text("\(label) \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(HyperliteTypography.regular(9).monospacedDigit())
            .foregroundStyle(HyperliteTheme.mutedText.color)
    }
}
