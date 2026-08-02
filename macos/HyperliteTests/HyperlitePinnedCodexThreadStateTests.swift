import Foundation

enum HyperlitePinnedCodexThreadStateTests {
    @MainActor
    static func run() async throws {
        testPresentation()
        try await testRefreshModes()
        try await testRetryResultClearsSignature()
        try await testOlderRefreshCannotOverwriteNewerSnapshot()
    }

    private static func testPresentation() {
        let zero = HyperlitePinnedCodexThreadSnapshot.current(threads: [], observedAt: pinnedTestDate)
        let zeroIndicator = HyperlitePinnedCodexThreadPresentation.indicator(
            snapshot: zero, lastAvailableAt: nil, timeZone: pinnedTestUTC
        )
        expectPinnedTest(zeroIndicator.systemImage == "pin" && zeroIndicator.countText == "0",
                         "a current zero should use the muted empty pin")

        let thread = pinnedTestThread(id: "one")
        let current = HyperlitePinnedCodexThreadSnapshot.current(
            threads: [thread], observedAt: pinnedTestDate
        )
        let currentIndicator = HyperlitePinnedCodexThreadPresentation.indicator(
            snapshot: current, lastAvailableAt: nil, timeZone: pinnedTestUTC
        )
        expectPinnedTest(currentIndicator.systemImage == "pin.fill" && currentIndicator.countText == "1",
                         "current membership should show the filled pin and count")

        let partial = HyperlitePinnedCodexThreadSnapshot.partial(
            threads: [thread], unresolvedMetadataCount: 1, observedAt: pinnedTestDate
        )
        expectPinnedTest(
            HyperlitePinnedCodexThreadPresentation.indicator(
                snapshot: partial, lastAvailableAt: nil, timeZone: pinnedTestUTC
            ).help.contains("1 pinned thread title is unavailable"),
            "partial help should explain missing titles"
        )

        let unavailable = HyperlitePinnedCodexThreadSnapshot.unavailable(
            checkedAt: pinnedTestDate, message: "Pinned Codex threads are unavailable"
        )
        let unavailableIndicator = HyperlitePinnedCodexThreadPresentation.indicator(
            snapshot: unavailable,
            lastAvailableAt: pinnedTestDate.addingTimeInterval(-60),
            timeZone: pinnedTestUTC
        )
        expectPinnedTest(
            unavailableIndicator.systemImage == "pin.slash" && unavailableIndicator.countText == "—",
            "unavailable membership should never display zero"
        )
        expectPinnedTest(unavailableIndicator.help.contains("last available 2026-08-02 10:59"),
                         "unavailable help should retain only the last observation time")
        expectPinnedTest(unavailableIndicator.accessibilityLabel.contains("last available 2026-08-02 10:59"),
                         "unavailable accessibility should include its reason and prior observation")
        expectPinnedTest(
            HyperlitePinnedCodexThreadPresentation.indicator(
                snapshot: nil, lastAvailableAt: nil, timeZone: pinnedTestUTC
            ).accessibilityLabel == "Pinned Codex threads loading",
            "initial loading should be explicit"
        )
    }

    @MainActor
    private static func testRetryResultClearsSignature() async throws {
        let unavailable = HyperlitePinnedCodexThreadSnapshot.unavailable(
            checkedAt: pinnedTestDate, message: "Source changed during refresh"
        )
        let recovered = HyperlitePinnedCodexThreadSnapshot.current(
            threads: [pinnedTestThread(id: "recovered")], observedAt: pinnedTestDate
        )
        let client = PinnedTestSequenceClient(results: [
            .retry(unavailable),
            .loaded(recovered, pinnedTestSignature(2)),
        ])
        let state = HyperlitePinnedCodexThreadState(
            client: client, now: { pinnedTestDate }, startImmediately: false
        )
        state.refresh(force: true)
        try await waitForPinnedTest { !state.isRefreshing }
        expectPinnedTest(state.snapshot?.availability == .unavailable,
                         "a torn read should publish unavailable")

        state.refreshIfSourceChanged()
        try await waitForPinnedTest { !state.isRefreshing }
        expectPinnedTest(state.snapshot?.threads.first?.id == "recovered",
                         "the next activation should retry after a torn read")
        let observedForces = await client.forces()
        expectPinnedTest(observedForces == [true, false],
                         "torn-read recovery should use the normal activation refresh")
    }

    @MainActor
    private static func testRefreshModes() async throws {
        let first = HyperlitePinnedCodexThreadSnapshot.current(
            threads: [pinnedTestThread(id: "first")], observedAt: pinnedTestDate
        )
        let second = HyperlitePinnedCodexThreadSnapshot.current(
            threads: [pinnedTestThread(id: "second")],
            observedAt: pinnedTestDate.addingTimeInterval(60)
        )
        let client = PinnedTestSequenceClient(results: [
            .loaded(first, pinnedTestSignature(1)),
            .unchanged(pinnedTestSignature(1)),
            .loaded(second, pinnedTestSignature(2)),
        ])
        let state = HyperlitePinnedCodexThreadState(
            client: client, now: { pinnedTestDate }, startImmediately: false
        )
        state.refresh(force: true)
        try await waitForPinnedTest { !state.isRefreshing }
        expectPinnedTest(state.snapshot?.threads.first?.id == "first", "startup refresh should load")

        state.refreshIfSourceChanged()
        try await waitForPinnedTest { !state.isRefreshing }
        expectPinnedTest(state.snapshot?.threads.first?.id == "first",
                         "an unchanged signature should retain the snapshot")

        state.refresh(force: true)
        try await waitForPinnedTest { !state.isRefreshing }
        expectPinnedTest(state.snapshot?.threads.first?.id == "second",
                         "force refresh should replace state")
        let observedForces = await client.forces()
        expectPinnedTest(observedForces == [true, false, true],
                         "state should distinguish activation and force refreshes")
    }

    @MainActor
    private static func testOlderRefreshCannotOverwriteNewerSnapshot() async throws {
        let client = PinnedTestControlledClient()
        let state = HyperlitePinnedCodexThreadState(
            client: client, now: { pinnedTestDate }, startImmediately: false
        )
        state.refresh(force: true)
        try await waitForPinnedTest { await client.pendingCount() == 1 }
        state.refresh(force: true)
        try await waitForPinnedTest { await client.pendingCount() == 2 }

        let newer = HyperlitePinnedCodexThreadSnapshot.current(
            threads: [pinnedTestThread(id: "newer")],
            observedAt: pinnedTestDate.addingTimeInterval(60)
        )
        await client.resume(index: 1, with: .loaded(newer, pinnedTestSignature(2)))
        try await waitForPinnedTest { !state.isRefreshing }
        expectPinnedTest(state.snapshot?.threads.first?.id == "newer", "newer refresh should publish")

        let older = HyperlitePinnedCodexThreadSnapshot.current(
            threads: [pinnedTestThread(id: "older")], observedAt: pinnedTestDate
        )
        await client.resume(index: 0, with: .loaded(older, pinnedTestSignature(1)))
        await Task.yield()
        expectPinnedTest(state.snapshot?.threads.first?.id == "newer",
                         "an older completion must not overwrite the current generation")
    }
}
