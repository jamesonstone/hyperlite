import Foundation

enum HyperlitePinnedCodexThreadAdapterTests {
    static func run() async throws {
        try testCodexHomeResolution()
        try await testAuthoritativeOrderingAndMetadata()
        try await testEmptyAndUnavailableMembership()
        try await testMalformedBoundedAndUnreadableMembership()
        try await testPartialMetadata()
        try await testTornReadRequestsRetry()
    }

    private static func testCodexHomeResolution() throws {
        try withPinnedTestDirectory { root in
            let configured = root.appendingPathComponent("configured", isDirectory: true)
            try FileManager.default.createDirectory(at: configured, withIntermediateDirectories: true)
            let configuredResult = HyperlitePinnedCodexThreadClient.resolveCodexHome(
                environment: ["CODEX_HOME": configured.path], defaultHome: root
            )
            expectPinnedTest(configuredResult == configured.standardizedFileURL,
                             "an absolute existing CODEX_HOME should win")

            let fallback = root.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL
            expectPinnedTest(
                HyperlitePinnedCodexThreadClient.resolveCodexHome(
                    environment: ["CODEX_HOME": "relative/codex"], defaultHome: root
                ) == fallback,
                "a relative CODEX_HOME should fall back"
            )
            expectPinnedTest(
                HyperlitePinnedCodexThreadClient.resolveCodexHome(
                    environment: ["CODEX_HOME": root.appendingPathComponent("missing").path],
                    defaultHome: root
                ) == fallback,
                "a missing CODEX_HOME should fall back"
            )
        }
    }

    private static func testAuthoritativeOrderingAndMetadata() async throws {
        try await withPinnedTestDirectory { home in
            try writePinnedGlobalState(
                home: home,
                text: """
                {"pinned-thread-ids":["two","one","two"],"private-marker":"must-not-leak"}
                """
            )
            try createPinnedTestDatabase(home: home, rows: [
                .init(id: "one", title: "First title", cwd: "/repo/one", updatedAt: 100),
                .init(
                    id: "two", name: "Named thread", title: "Second title",
                    cwd: "/repo/two", updatedAt: 200
                ),
                .init(id: "extra", title: "Not pinned", cwd: "/repo/extra", isPinned: true),
            ])
            let snapshot = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(snapshot.availability == .current, "complete metadata should be current")
            expectPinnedTest(snapshot.authoritativeCount == 2,
                             "duplicates should not increase the count")
            expectPinnedTest(snapshot.threads.map(\.id) == ["two", "one"],
                             "first-seen pin ordering should be retained")
            expectPinnedTest(snapshot.threads[0].displayTitle == "Named thread",
                             "a user-facing name should win over title")
            expectPinnedTest(snapshot.threads[0].directoryName == "two", "CWD basename should render")
            expectPinnedTest(snapshot.threads[0].updatedAt == Date(timeIntervalSince1970: 200),
                             "SQLite update time should decode")
            expectPinnedTest(!snapshot.threads.contains { $0.id == "extra" },
                             "metadata rows and is_pinned must never add membership")
        }
    }

    private static func testEmptyAndUnavailableMembership() async throws {
        try await withPinnedTestDirectory { home in
            try writePinnedGlobalState(home: home, text: "{\"pinned-thread-ids\":[]}")
            let empty = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(empty.availability == .current && empty.authoritativeCount == 0,
                             "an explicit empty array should be a current zero")

            try writePinnedGlobalState(home: home, text: "{\"other\":[]}")
            let missingKey = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(missingKey.availability == .unavailable,
                             "a missing membership key must be unavailable")
            expectPinnedTest(missingKey.authoritativeCount == nil,
                             "unavailable membership must not expose a zero count")

            try FileManager.default.removeItem(
                at: home.appendingPathComponent(".codex-global-state.json")
            )
            let missingFile = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(missingFile.availability == .unavailable,
                             "a missing global-state file must be unavailable")
        }
    }

    private static func testMalformedBoundedAndUnreadableMembership() async throws {
        try await withPinnedTestDirectory { home in
            try writePinnedGlobalState(home: home, text: "{not-json")
            let malformed = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(malformed.availability == .unavailable,
                             "malformed JSON must be unavailable")

            try writePinnedGlobalState(home: home, text: "{\"pinned-thread-ids\":[\"one\",7]}")
            let wrongType = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(wrongType.availability == .unavailable,
                             "non-string pin entries must be unavailable")

            try writePinnedGlobalState(home: home, text: "{\"pinned-thread-ids\":[\"\"]}")
            let emptyID = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(emptyID.availability == .unavailable,
                             "empty opaque IDs must be unavailable")

            let tooMany = Array(repeating: "duplicate", count: 10_001)
            let data = try JSONSerialization.data(withJSONObject: ["pinned-thread-ids": tooMany])
            try data.write(to: home.appendingPathComponent(".codex-global-state.json"))
            let excessive = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(excessive.availability == .unavailable,
                             "the pre-deduplication pin count must remain bounded")

            let stateURL = home.appendingPathComponent(".codex-global-state.json")
            FileManager.default.createFile(atPath: stateURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: stateURL)
            try handle.truncate(atOffset: UInt64(HyperlitePinnedCodexThreadClient.maxGlobalStateBytes + 1))
            try handle.close()
            let oversized = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(oversized.availability == .unavailable,
                             "an oversized global-state file must be unavailable")

            try writePinnedGlobalState(home: home, text: "{\"pinned-thread-ids\":[\"secret-marker\"]}")
            let client = HyperlitePinnedCodexThreadClient(
                environment: ["CODEX_HOME": home.path], defaultHome: home,
                dataLoader: { _, _ in throw PinnedTestError("raw secret-marker value") }
            )
            let unreadable = try await pinnedTestSnapshot(
                from: client.load(previousSignature: nil, force: true, checkedAt: pinnedTestDate)
            )
            expectPinnedTest(unreadable.availability == .unavailable,
                             "an unreadable regular file must be unavailable")
            expectPinnedTest(!(unreadable.message ?? "").contains("secret-marker"),
                             "raw state and underlying errors must not appear in diagnostics")
        }
    }

    private static func testPartialMetadata() async throws {
        try await withPinnedTestDirectory { home in
            try writePinnedGlobalState(
                home: home,
                text: "{\"pinned-thread-ids\":[\"resolved\",\"missing\",\"untitled\"]}"
            )
            try createPinnedTestDatabase(home: home, rows: [
                .init(id: "resolved", title: "Resolved", cwd: "/repo/resolved"),
                .init(id: "untitled", title: "", cwd: "/repo/untitled"),
                .init(id: "not-a-member", title: "Extra", isPinned: true),
            ])
            let partial = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(partial.availability == .partial, "missing titles should be partial")
            expectPinnedTest(partial.authoritativeCount == 3,
                             "partial metadata must retain membership")
            expectPinnedTest(partial.unresolvedMetadataCount == 2,
                             "missing and untitled rows should both be unresolved")
            expectPinnedTest(partial.threads[1].displayTitle == "missing",
                             "a missing row should use its opaque ID")
            expectPinnedTest(partial.threads[2].directoryName == "untitled",
                             "optional directory metadata should survive an untitled row")

            try FileManager.default.removeItem(at: home.appendingPathComponent("state_5.sqlite"))
            let noDatabase = try await loadPinnedTestSnapshot(home: home)
            expectPinnedTest(noDatabase.availability == .partial && noDatabase.authoritativeCount == 3,
                             "SQLite unavailability must preserve the authoritative count")
            expectPinnedTest(noDatabase.unresolvedMetadataCount == 3,
                             "all titles should be unresolved without SQLite")
        }
    }

    private static func testTornReadRequestsRetry() async throws {
        try await withPinnedTestDirectory { home in
            try writePinnedGlobalState(home: home, text: "{\"pinned-thread-ids\":[]}")
            let client = HyperlitePinnedCodexThreadClient(
                environment: ["CODEX_HOME": home.path], defaultHome: home,
                dataLoader: { url, limit in
                    let data = try HyperlitePinnedCodexThreadClient.readBoundedFile(url, limit: limit)
                    var changed = data
                    changed.append(0x20)
                    try changed.write(to: url)
                    return data
                }
            )
            let result = try await client.load(
                previousSignature: nil, force: true, checkedAt: pinnedTestDate
            )
            guard case let .retry(snapshot) = result else {
                throw PinnedTestError("a repeatedly changing source should request a retry")
            }
            expectPinnedTest(snapshot.availability == .unavailable,
                             "a torn read should fail closed until the next activation")
        }
    }
}
