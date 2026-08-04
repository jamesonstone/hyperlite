import Foundation

enum HyperliteNotepadTests {
    @MainActor
    static func run() async throws {
        expect(
            HyperliteNotepadState.autosaveDelay == .seconds(3),
            "production autosave should wait for three idle seconds"
        )
        try await testPinnedAndDailyAutosave()
        try await testNavigationFlushesBeforeDirectLoad()
        try await testCurrentDateRolloverPreservesHistoricalSelection()
        try await testHistoricalDateRebasesAcrossTimeZoneChange()
        try await testDateRefreshQueuesDuringNavigation()
        try await testSearchIndexExactAndSemantic()
        try await testDateAndSizeBoundaries()
        await HyperliteNotepadRecoveryTests.run()
    }

    @MainActor
    private static func testCurrentDateRolloverPreservesHistoricalSelection() async throws {
        let client = NotepadClient(documents: [
            .pinned: document(.pinned, content: "Pinned"),
            .daily("2026-08-01"): document(.daily("2026-08-01"), content: "history"),
            .daily("2026-08-02"): document(.daily("2026-08-02"), content: "today"),
            .daily("2026-08-03"): document(.daily("2026-08-03"), content: "next day"),
        ])
        let state = makeState(client: client)
        await state.waitUntilLoaded()
        await client.resetOperations()

        state.focusPinned()
        expect(state.updateDaily("unsaved today"), "the prior daily draft should accept edits")
        await state.refreshDailyDateIfNeeded(
            now: Date(timeIntervalSince1970: 1_785_672_000 + 86_400)
        )
        expect(state.selectedDateIdentifier == "2026-08-03", "today should roll to the new day")
        expect(state.dailyText == "next day", "rollover should load the new day's content")
        expect(state.activeTab == .notepad, "rollover should preserve the active Notepad tab")
        let rolloverOperations = await client.recordedOperations()
        expect(
            Array(rolloverOperations.prefix(2)) == ["save:2026-08-02", "load:2026-08-03"],
            "rollover should flush the prior day before one direct load"
        )

        await state.selectDateIdentifier("2026-08-01")
        await client.resetOperations()
        await state.refreshDailyDateIfNeeded(
            now: Date(timeIntervalSince1970: 1_785_672_000 + 172_800)
        )
        expect(
            state.selectedDateIdentifier == "2026-08-01",
            "refresh should preserve an explicitly selected historical day"
        )
        let historicalOperations = await client.recordedOperations()
        expect(
            historicalOperations.isEmpty,
            "preserving historical navigation should not touch storage"
        )

        await state.selectDateIdentifier("2026-08-02")
        await client.resetOperations()
        await state.refreshDailyDateIfNeeded(
            now: Date(timeIntervalSince1970: 1_785_672_000 + 172_800)
        )
        expect(
            state.selectedDateIdentifier == "2026-08-04",
            "selecting today should restore current-day following"
        )
    }

    @MainActor
    private static func testHistoricalDateRebasesAcrossTimeZoneChange() async throws {
        var currentCalendar = Calendar(identifier: .gregorian)
        currentCalendar.timeZone = TimeZone(secondsFromGMT: -5 * 3_600)!
        let currentNow = noteDate("2026-08-02", calendar: currentCalendar)
        let client = NotepadClient(documents: [
            .pinned: document(.pinned, content: "Pinned"),
            .daily("2026-08-01"): document(.daily("2026-08-01"), content: "history"),
            .daily("2026-08-02"): document(.daily("2026-08-02"), content: "today"),
        ])
        let state = makeState(
            client: client,
            calendar: { currentCalendar },
            now: { currentNow }
        )
        await state.waitUntilLoaded()
        await state.selectDateIdentifier("2026-08-01")
        await client.resetOperations()

        currentCalendar.timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
        expect(
            HyperliteNoteDate.identifier(for: state.selectedDate, calendar: currentCalendar) ==
                "2026-07-31",
            "the test setup should move the old absolute date across a calendar boundary"
        )
        await state.refreshDailyDateIfNeeded(now: currentNow)
        expect(
            state.selectedDateIdentifier == "2026-08-01",
            "time-zone refresh should preserve the historical daily identifier"
        )
        expect(
            HyperliteNoteDate.identifier(for: state.selectedDate, calendar: currentCalendar) ==
                state.selectedDateIdentifier,
            "the DatePicker date should rebase to the historical identifier in the new time zone"
        )
        let operations = await client.recordedOperations()
        expect(operations.isEmpty, "rebasing historical presentation should not touch storage")
    }

    @MainActor
    private static func testDateRefreshQueuesDuringNavigation() async throws {
        var currentCalendar = Calendar(identifier: .gregorian)
        currentCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var currentNow = noteDate("2026-08-02", calendar: currentCalendar)
        let loadGate = DailyLoadGate()
        let client = NotepadClient(
            documents: [
                .pinned: document(.pinned, content: "Pinned"),
                .daily("2026-08-02"): document(.daily("2026-08-02"), content: "day two"),
                .daily("2026-08-03"): document(.daily("2026-08-03"), content: "day three"),
                .daily("2026-08-04"): document(.daily("2026-08-04"), content: "day four"),
            ],
            delayedLoadDate: "2026-08-03",
            loadGate: loadGate
        )
        let state = makeState(
            client: client,
            calendar: { currentCalendar },
            now: { currentNow }
        )
        await state.waitUntilLoaded()
        await client.resetOperations()

        currentNow = noteDate("2026-08-03", calendar: currentCalendar)
        let firstRefresh = Task { await state.refreshDailyDateIfNeeded() }
        await loadGate.waitUntilArrived()
        expect(state.isNavigating, "the first daily load should remain in flight")

        currentNow = noteDate("2026-08-04", calendar: currentCalendar)
        await state.refreshDailyDateIfNeeded()
        await loadGate.open()
        await firstRefresh.value

        expect(
            state.selectedDateIdentifier == "2026-08-04",
            "a queued refresh should re-evaluate the day after navigation completes"
        )
        expect(state.dailyText == "day four", "the queued refresh should load the latest day")
        let operations = await client.recordedOperations()
        expect(
            operations == ["load:2026-08-03", "load:2026-08-04"],
            "the delayed day and the re-evaluated current day should each load once"
        )
    }

    @MainActor
    private static func testPinnedAndDailyAutosave() async throws {
        let initialDocuments: [HyperliteNoteID: HyperliteNoteDocument] = [
            .pinned: document(.pinned, content: "Persisted context\n"),
            .daily("2026-08-02"): document(.daily("2026-08-02"), content: "", exists: false),
        ]
        let client = NotepadClient(
            documents: initialDocuments,
            indexSnapshot: Array(initialDocuments.values),
            indexDelay: .milliseconds(80)
        )
        let state = makeState(client: client)
        await state.waitUntilLoaded()
        expect(state.pinnedText == "Persisted context\n", "pinned note should load")
        expect(state.dailyText.isEmpty, "missing today's note should load as an empty draft")
        expect(state.selectedDateIdentifier == "2026-08-02", "today should open by default")
        expect(state.activeTab == .daily, "Daily should be the default tab")
        expect(
            state.displayName(for: state.selectedDateIdentifier) == "August 2nd, 2026",
            "the Daily tab should display the full selected date"
        )
        let initialSaves = await client.savedValues()
        expect(initialSaves.isEmpty, "loading an empty day should not create its file")

        expect(state.updatePinned("first"), "first pinned edit should be accepted")
        expect(state.updatePinned("second"), "latest pinned edit should be accepted")
        expect(state.updateDaily("daily first"), "first daily edit should be accepted")
        expect(state.updateDaily("daily second"), "latest daily edit should be accepted")
        try? await Task.sleep(for: .milliseconds(70))
        let didFlush = await state.flush()
        expect(didFlush, "both active drafts should flush")
        let saved = await client.savedValues()
        expect(saved[.pinned] == "second", "autosave should persist only the latest pinned edit")
        expect(
            saved[.daily("2026-08-02")] == "daily second",
            "autosave should lazily create only the latest daily edit"
        )
        expect(!state.isDirty, "successful autosaves should clear both dirty drafts")
        await state.waitUntilIndexed()
        let updatedResults = await state.searchNotes("daily second")
        expect(
            updatedResults.first?.noteID == .daily("2026-08-02"),
            "a stale initial scan must not replace content saved while indexing"
        )
    }

    @MainActor
    private static func testNavigationFlushesBeforeDirectLoad() async throws {
        let client = NotepadClient(documents: [
            .pinned: document(.pinned, content: "Pinned"),
            .daily("2026-08-02"): document(.daily("2026-08-02"), content: "today"),
            .daily("2026-08-03"): document(.daily("2026-08-03"), content: "tomorrow"),
        ])
        let state = makeState(client: client)
        await state.waitUntilLoaded()
        await state.waitUntilIndexed()
        await client.resetOperations()

        expect(state.updateDaily("unsaved today"), "daily edit should be accepted")
        await state.selectDateIdentifier("2026-08-03", focus: true)
        expect(state.selectedDateIdentifier == "2026-08-03", "calendar selection should open its day")
        expect(state.dailyText == "tomorrow", "navigation should load the selected file")
        expect(state.activeTab == .daily, "date selection should activate Daily")
        expect(state.focusRequest?.target == .daily, "requested result should focus daily editor")
        let operations = await client.recordedOperations()
        expect(
            Array(operations.prefix(2)) == ["save:2026-08-02", "load:2026-08-03"],
            "navigation should flush the current day before one direct target read"
        )
        let indexRequests = await client.indexRequestCount()
        expect(indexRequests == 1, "navigation should not rescan historical notes")

        state.focusPinned()
        expect(state.activeTab == .notepad, "Notepad selection should show the durable note")
        expect(state.focusRequest?.target == .pinned, "pinned search result should request pinned focus")
        state.focusDaily()
        expect(state.activeTab == .daily, "Daily selection should restore the dated note")
        expect(state.focusRequest?.target == .daily, "Daily selection should request daily focus")
        state.focusPinned()
        await state.selectDateIdentifier("2026-08-03", focus: true)
        expect(state.activeTab == .daily, "selecting the current calendar date should activate Daily")
        expect(
            state.focusRequest?.target == .daily,
            "selecting the current calendar date should focus Daily without reloading"
        )
    }

    private static func testSearchIndexExactAndSemantic() async throws {
        let index = HyperliteNoteSearchIndex { text in
            let text = text.lowercased()
            if text.contains("storage") || text.contains("database") || text.contains("postgres") ||
                text == "pinned.md"
            {
                return [1, 0]
            }
            if text.contains("ocean") || text.contains("marine") { return [0, 1] }
            return nil
        }
        let pinned = document(.pinned, content: "Repository paths and stable identifiers")
        let database = document(
            .daily("2026-08-01"),
            content: "Configured the PostgreSQL database pool",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let ocean = document(
            .daily("2026-08-02"),
            content: "Reviewed marine habitat notes",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        await index.replace(with: [pinned, database, ocean])

        let filenameResults = await index.search("pinned.md")
        expect(
            filenameResults.first?.noteID == .pinned && filenameResults.first?.matchKind == .exact,
            "literal filename search should return pinned first"
        )
        expect(filenameResults.count == 1, "literal matches should suppress semantic noise")
        let dateResults = await index.search("2026-08-02")
        expect(
            dateResults.first?.noteID == .daily("2026-08-02"),
            "literal date search should return its daily note"
        )
        let semanticResults = await index.search("storage")
        expect(
            semanticResults.first?.noteID == .daily("2026-08-01") &&
                semanticResults.first?.matchKind == .semantic,
            "semantic search should retrieve related database content"
        )
    }

    @MainActor
    private static func testDateAndSizeBoundaries() async throws {
        let client = NotepadClient(documents: [
            .pinned: document(.pinned, content: "Pinned"),
            .daily("2026-08-02"): document(.daily("2026-08-02"), content: "Today"),
        ])
        let state = makeState(client: client)
        await state.waitUntilLoaded()
        let previous = state.pinnedText
        let oversized = String(repeating: "x", count: HyperliteNotepadState.maxBytes + 1)
        expect(!state.updatePinned(oversized), "oversized edits should be rejected")
        expect(state.pinnedText == previous, "rejected content should not replace the draft")
        await state.selectDateIdentifier("2026-02-30")
        expect(
            state.selectedDateIdentifier == "2026-08-02",
            "an invalid ISO day should not change the selected note"
        )
    }

    @MainActor
    private static func makeState(
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

    private static func noteDate(_ identifier: String, calendar: Calendar) -> Date {
        guard let date = HyperliteNoteDate.date(from: identifier, calendar: calendar) else {
            fatalError("invalid test date: \(identifier)")
        }
        return date
    }

    private static func document(
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}

private actor DailyLoadGate {
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

private actor NotepadClient: HyperliteNotepadClient {
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
