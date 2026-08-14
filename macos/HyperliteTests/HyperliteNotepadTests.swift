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
}
