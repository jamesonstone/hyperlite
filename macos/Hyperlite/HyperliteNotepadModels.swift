import Foundation

enum HyperliteNoteKind: String, Codable, Sendable {
    case pinned
    case daily
}

struct HyperliteNoteDocument: Codable, Equatable, Sendable {
    let kind: HyperliteNoteKind
    let date: String?
    let filename: String
    let content: String
    let path: String
    let updatedAt: Date?
    let exists: Bool

    var id: HyperliteNoteID {
        kind == .pinned ? .pinned : .daily(date ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case kind, date, filename, content, path, exists
        case updatedAt = "updated_at"
    }
}

enum HyperliteNoteID: Hashable, Sendable {
    case pinned
    case daily(String)
}

enum HyperliteNotepadTab: Equatable {
    case notepad
    case daily
}

struct HyperliteNoteSearchResult: Equatable, Identifiable, Sendable {
    enum MatchKind: Equatable, Sendable {
        case exact
        case semantic
    }

    let noteID: HyperliteNoteID
    let filename: String
    let date: String?
    let snippet: String
    let matchKind: MatchKind
    let score: Double

    var id: String {
        switch noteID {
        case .pinned: "note:pinned"
        case let .daily(date): "note:daily:\(date)"
        }
    }
}

struct HyperliteNotepadFocusRequest: Equatable {
    enum Target: Equatable {
        case pinned
        case daily
    }

    let target: Target
    let generation: Int
}

enum HyperliteNoteDate {
    static func identifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(from identifier: String, calendar: Calendar) -> Date? {
        let parts = identifier.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              self.identifier(for: date, calendar: calendar) == identifier
        else { return nil }
        return date
    }

    @MainActor
    static func displayName(for identifier: String, calendar: Calendar) -> String {
        guard let date = date(from: identifier, calendar: calendar) else { return identifier }
        let day = calendar.component(.day, from: date)
        let monthIndex = calendar.component(.month, from: date) - 1
        let year = calendar.component(.year, from: date)
        let ordinal = ordinalFormatter.string(from: NSNumber(value: day)) ?? String(day)
        let month = monthNames.indices.contains(monthIndex)
            ? monthNames[monthIndex]
            : String(monthIndex + 1)
        return "\(month) \(ordinal), \(year)"
    }

    @MainActor private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .ordinal
        return formatter
    }()

    @MainActor private static let monthNames: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.monthSymbols
    }()
}

protocol HyperliteNotepadClient: Sendable {
    func loadPinned() async throws -> HyperliteNoteDocument
    func loadDaily(date: String) async throws -> HyperliteNoteDocument
    func savePinned(_ content: String) async throws -> HyperliteNoteDocument
    func saveDaily(date: String, content: String) async throws -> HyperliteNoteDocument
    func indexDocuments() async throws -> [HyperliteNoteDocument]
}

struct HyperliteProcessNotepadClient: HyperliteNotepadClient {
    func loadPinned() async throws -> HyperliteNoteDocument {
        try await document(
            arguments: ["notepad", "show", "--json"], operation: "load pinned note"
        )
    }

    func loadDaily(date: String) async throws -> HyperliteNoteDocument {
        try await document(
            arguments: ["notepad", "show", "--date", date, "--json"],
            operation: "load daily note"
        )
    }

    func savePinned(_ content: String) async throws -> HyperliteNoteDocument {
        try await document(
            arguments: ["notepad", "set", "--stdin", "--json"],
            operation: "save pinned note",
            standardInput: Data(content.utf8)
        )
    }

    func saveDaily(date: String, content: String) async throws -> HyperliteNoteDocument {
        try await document(
            arguments: ["notepad", "set", "--stdin", "--date", date, "--json"],
            operation: "save daily note",
            standardInput: Data(content.utf8)
        )
    }

    func indexDocuments() async throws -> [HyperliteNoteDocument] {
        let data = try await HyperliteProcess.run(
            arguments: ["notepad", "index"], operation: "index notes"
        )
        return try HyperliteJSON.decoder.decode([HyperliteNoteDocument].self, from: data)
    }

    private func document(
        arguments: [String],
        operation: String,
        standardInput: Data? = nil
    ) async throws -> HyperliteNoteDocument {
        let data = try await HyperliteProcess.run(
            arguments: arguments,
            operation: operation,
            standardInput: standardInput
        )
        return try HyperliteJSON.decoder.decode(HyperliteNoteDocument.self, from: data)
    }
}

enum HyperliteNotepadError: LocalizedError {
    case invalidDate(String)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case let .invalidDate(date): "Invalid daily note date: \(date)"
        case .tooLarge: "Each note is limited to 256 KiB"
        }
    }
}
