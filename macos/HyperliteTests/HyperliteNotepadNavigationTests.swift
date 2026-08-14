import Foundation

extension HyperliteNotepadTests {
    @MainActor
    static func testCurrentDateRolloverPreservesHistoricalSelection() async throws {
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
    static func testHistoricalDateRebasesAcrossTimeZoneChange() async throws {
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
    static func testDateRefreshQueuesDuringNavigation() async throws {
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
    static func testNavigationFlushesBeforeDirectLoad() async throws {
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
}
