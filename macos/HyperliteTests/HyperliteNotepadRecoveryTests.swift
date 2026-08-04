import Foundation

enum HyperliteNotepadRecoveryTests {
    @MainActor
    static func run() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let state = HyperliteNotepadState(
            client: IndexRecoveryClient(),
            searchIndex: HyperliteNoteSearchIndex(vectorProvider: { _ in nil }),
            autosaveDelay: .milliseconds(20),
            calendar: { calendar },
            now: { Date(timeIntervalSince1970: 1_785_672_000) }
        )
        await state.waitUntilLoaded()
        await state.waitUntilIndexed()
        expect(!state.isIndexReady, "the first simulated index failure should remain visible")
        state.rebuildSearchIndex()
        await state.waitUntilIndexed()
        expect(state.isIndexReady, "a failed note index should support an explicit rebuild")
        expect(state.errorMessage == nil, "a successful rebuild should clear the index error")
        let results = await state.searchNotes("recovered")
        expect(results.first?.noteID == .pinned, "the rebuilt index should be searchable")

        expect(state.updatePinned("pinned index update"), "the pinned update should be accepted")
        expect(state.updateDaily("daily index update"), "the daily update should be accepted")
        let didFlush = await state.flush()
        expect(didFlush, "consecutive pinned and daily updates should flush")
        await state.waitUntilIndexUpdates()
        let pinnedResults = await state.searchNotes("pinned index update")
        let dailyResults = await state.searchNotes("daily index update")
        expect(
            pinnedResults.first?.noteID == .pinned,
            "a following daily save must not cancel the pinned index update"
        )
        expect(
            dailyResults.first?.noteID == .daily("2026-08-02"),
            "the daily index update should remain searchable"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}

private actor IndexRecoveryClient: HyperliteNotepadClient {
    private var indexAttempts = 0

    func loadPinned() async throws -> HyperliteNoteDocument { pinned() }

    func loadDaily(date: String) async throws -> HyperliteNoteDocument {
        HyperliteNoteDocument(
            kind: .daily, date: date, filename: "\(date).md", content: "",
            path: "/notes/daily/\(date).md", updatedAt: nil, exists: false
        )
    }

    func savePinned(_ content: String) async throws -> HyperliteNoteDocument { pinned(content) }

    func saveDaily(date: String, content: String) async throws -> HyperliteNoteDocument {
        HyperliteNoteDocument(
            kind: .daily, date: date, filename: "\(date).md", content: content,
            path: "/notes/daily/\(date).md", updatedAt: Date(), exists: true
        )
    }

    func indexDocuments() async throws -> [HyperliteNoteDocument] {
        indexAttempts += 1
        if indexAttempts == 1 { throw CocoaError(.fileReadUnknown) }
        return [pinned()]
    }

    private func pinned(_ content: String = "recovered index content") -> HyperliteNoteDocument {
        HyperliteNoteDocument(
            kind: .pinned, date: nil, filename: "pinned.md", content: content,
            path: "/notes/pinned.md", updatedAt: Date(timeIntervalSince1970: 100), exists: true
        )
    }
}
