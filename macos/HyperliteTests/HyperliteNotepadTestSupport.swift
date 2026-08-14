import Foundation

extension HyperliteNotepadTests {
    @MainActor
    static func makeState(
        client: NotepadClient,
        calendar: (() -> Calendar)? = nil,
        now: (() -> Date)? = nil
    ) -> HyperliteNotepadState {
        var fixedCalendar = Calendar(identifier: .gregorian)
        fixedCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return HyperliteNotepadState(
            client: client,
            searchIndex: HyperliteNoteSearchIndex(vectorProvider: { _ in nil }),
            autosaveDelay: .milliseconds(20),
            calendar: calendar ?? { fixedCalendar },
            now: now ?? { Date(timeIntervalSince1970: 1_785_672_000) }
        )
    }

    static func noteDate(_ identifier: String, calendar: Calendar) -> Date {
        guard let date = HyperliteNoteDate.date(from: identifier, calendar: calendar) else {
            fatalError("invalid test date: \(identifier)")
        }
        return date
    }

    static func document(
        _ id: HyperliteNoteID,
        content: String,
        exists: Bool = true,
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> HyperliteNoteDocument {
        switch id {
        case .pinned:
            HyperliteNoteDocument(
                kind: .pinned, date: nil, filename: "pinned.md", content: content,
                path: "/notes/pinned.md", updatedAt: exists ? updatedAt : nil, exists: exists
            )
        case let .daily(date):
            HyperliteNoteDocument(
                kind: .daily, date: date, filename: "\(date).md", content: content,
                path: "/notes/daily/\(date).md", updatedAt: exists ? updatedAt : nil, exists: exists
            )
        }
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}

actor DailyLoadGate {
    private var arrived = false
    private var isOpen = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func arriveAndWait() async {
        arrived = true
        arrivalWaiters.forEach { $0.resume() }
        arrivalWaiters.removeAll()
        guard !isOpen else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilArrived() async {
        guard !arrived else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func open() {
        isOpen = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

actor NotepadClient: HyperliteNotepadClient {
    private var documents: [HyperliteNoteID: HyperliteNoteDocument]
    private var saves: [HyperliteNoteID: String] = [:]
    private var operations: [String] = []
    private var indexRequests = 0
    private var updateCounter: TimeInterval = 1_000
    private let indexSnapshot: [HyperliteNoteDocument]?
    private let indexDelay: Duration
    private let delayedLoadDate: String?
    private let loadGate: DailyLoadGate?

    init(
        documents: [HyperliteNoteID: HyperliteNoteDocument],
        indexSnapshot: [HyperliteNoteDocument]? = nil,
        indexDelay: Duration = .zero,
        delayedLoadDate: String? = nil,
        loadGate: DailyLoadGate? = nil
    ) {
        self.documents = documents
        self.indexSnapshot = indexSnapshot
        self.indexDelay = indexDelay
        self.delayedLoadDate = delayedLoadDate
        self.loadGate = loadGate
    }

    func loadPinned() async throws -> HyperliteNoteDocument {
        operations.append("load:pinned")
        return documents[.pinned] ?? missing(.pinned)
    }

    func loadDaily(date: String) async throws -> HyperliteNoteDocument {
        operations.append("load:\(date)")
        if date == delayedLoadDate, let loadGate { await loadGate.arriveAndWait() }
        return documents[.daily(date)] ?? missing(.daily(date))
    }

    func savePinned(_ content: String) async throws -> HyperliteNoteDocument {
        try save(.pinned, content: content)
    }

    func saveDaily(date: String, content: String) async throws -> HyperliteNoteDocument {
        try save(.daily(date), content: content)
    }

    func indexDocuments() async throws -> [HyperliteNoteDocument] {
        indexRequests += 1
        let snapshot = indexSnapshot ?? Array(documents.values)
        try await Task.sleep(for: indexDelay)
        return snapshot
    }

    func savedValues() -> [HyperliteNoteID: String] { saves }
    func recordedOperations() -> [String] { operations }
    func indexRequestCount() -> Int { indexRequests }
    func resetOperations() { operations = [] }

    private func save(
        _ id: HyperliteNoteID,
        content: String
    ) throws -> HyperliteNoteDocument {
        updateCounter += 1
        let document: HyperliteNoteDocument
        switch id {
        case .pinned:
            operations.append("save:pinned")
            document = HyperliteNoteDocument(
                kind: .pinned, date: nil, filename: "pinned.md", content: content,
                path: "/notes/pinned.md", updatedAt: Date(timeIntervalSince1970: updateCounter),
                exists: true
            )
        case let .daily(date):
            operations.append("save:\(date)")
            document = HyperliteNoteDocument(
                kind: .daily, date: date, filename: "\(date).md", content: content,
                path: "/notes/daily/\(date).md",
                updatedAt: Date(timeIntervalSince1970: updateCounter), exists: true
            )
        }
        documents[id] = document
        saves[id] = content
        return document
    }

    private func missing(_ id: HyperliteNoteID) -> HyperliteNoteDocument {
        switch id {
        case .pinned:
            HyperliteNoteDocument(
                kind: .pinned, date: nil, filename: "pinned.md", content: "",
                path: "/notes/pinned.md", updatedAt: nil, exists: false
            )
        case let .daily(date):
            HyperliteNoteDocument(
                kind: .daily, date: date, filename: "\(date).md", content: "",
                path: "/notes/daily/\(date).md", updatedAt: nil, exists: false
            )
        }
    }
}
