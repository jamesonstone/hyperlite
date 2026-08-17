import Foundation

enum HyperliteWorkspace: String, CaseIterable, Identifiable {
    case dashboard
    case pinboard
    case sessions

    var id: String { rawValue }
}

struct HyperlitePinboardSize: Codable, Equatable, Sendable {
    let width: Double
    let height: Double
}

struct HyperlitePinboardFrame: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct HyperlitePinboardSection: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let frame: HyperlitePinboardFrame
}

struct HyperlitePinboardNoteLayout: Codable, Equatable, Identifiable, Sendable {
    let noteID: String
    let sectionID: String
    let frame: HyperlitePinboardFrame

    var id: String { noteID }

    enum CodingKeys: String, CodingKey {
        case frame
        case noteID = "note_id"
        case sectionID = "section_id"
    }
}

struct HyperlitePinboardBoard: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let size: HyperlitePinboardSize
    let sections: [HyperlitePinboardSection]
    let notes: [HyperlitePinboardNoteLayout]

    enum CodingKeys: String, CodingKey {
        case size, sections, notes
        case schemaVersion = "schema_version"
    }
}

struct HyperlitePinboardNote: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let createdAt: Date
    let updatedAt: Date
    let forkedFrom: String?
    let archivedAt: Date?
    let archivedFromSectionID: String?
    let archivedFromSectionTitle: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case forkedFrom = "forked_from"
        case archivedAt = "archived_at"
        case archivedFromSectionID = "archived_from_section_id"
        case archivedFromSectionTitle = "archived_from_section_title"
    }
}

struct HyperlitePinboardSnapshot: Codable, Equatable, Sendable {
    let board: HyperlitePinboardBoard
    let notes: [HyperlitePinboardNote]
    let archive: [HyperlitePinboardNote]

    var notesByID: [String: HyperlitePinboardNote] {
        Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

enum HyperlitePinboardMutationKind: String, Codable, Sendable {
    case addSection = "add_section"
    case renameSection = "rename_section"
    case updateSectionFrame = "update_section_frame"
    case deleteSection = "delete_section"
    case addNote = "add_note"
    case updateNote = "update_note"
    case moveNote = "move_note"
    case forkNote = "fork_note"
    case archiveNote = "archive_note"
    case restoreNote = "restore_note"
}

struct HyperlitePinboardMutation: Codable, Equatable, Sendable {
    let kind: HyperlitePinboardMutationKind
    var sectionID: String?
    var noteID: String?
    var title: String?
    var description: String?
    var frame: HyperlitePinboardFrame?
    var archiveNotes: Bool?

    init(
        kind: HyperlitePinboardMutationKind,
        sectionID: String? = nil,
        noteID: String? = nil,
        title: String? = nil,
        description: String? = nil,
        frame: HyperlitePinboardFrame? = nil,
        archiveNotes: Bool? = nil
    ) {
        self.kind = kind
        self.sectionID = sectionID
        self.noteID = noteID
        self.title = title
        self.description = description
        self.frame = frame
        self.archiveNotes = archiveNotes
    }

    enum CodingKeys: String, CodingKey {
        case kind, title, description, frame
        case sectionID = "section_id"
        case noteID = "note_id"
        case archiveNotes = "archive_notes"
    }
}

enum HyperlitePinboardCommand: Equatable {
    case addNote
    case addSection
    case openArchive
}

struct HyperlitePinboardCommandRequest: Equatable, Identifiable {
    let id: Int
    let command: HyperlitePinboardCommand
}
