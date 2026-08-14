import Foundation

extension HyperliteNotepadTests {
    @MainActor
    static func testPinnedAndDailyAutosave() async throws {
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
    static func testDateAndSizeBoundaries() async throws {
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
}
