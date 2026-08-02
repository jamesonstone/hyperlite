enum HyperlitePinnedCodexThreadTests {
    @MainActor
    static func run() async throws {
        try await HyperlitePinnedCodexThreadAdapterTests.run()
        try await HyperlitePinnedCodexThreadStateTests.run()
    }
}
