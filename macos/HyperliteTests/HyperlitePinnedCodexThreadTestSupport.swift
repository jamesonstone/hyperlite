import Foundation
import SQLite3

private let pinnedTestSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

let pinnedTestDate = Date(timeIntervalSince1970: 1_785_668_400)
let pinnedTestUTC = TimeZone(secondsFromGMT: 0)!

func expectPinnedTest(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func writePinnedGlobalState(home: URL, text: String) throws {
    try Data(text.utf8).write(to: home.appendingPathComponent(".codex-global-state.json"))
}

func loadPinnedTestSnapshot(home: URL) async throws -> HyperlitePinnedCodexThreadSnapshot {
    let client = HyperlitePinnedCodexThreadClient(
        environment: ["CODEX_HOME": home.path], defaultHome: home
    )
    return try await pinnedTestSnapshot(
        from: client.load(previousSignature: nil, force: true, checkedAt: pinnedTestDate)
    )
}

func pinnedTestSnapshot(
    from result: HyperlitePinnedCodexThreadLoadResult
) throws -> HyperlitePinnedCodexThreadSnapshot {
    switch result {
    case let .loaded(snapshot, _): return snapshot
    case let .retry(snapshot): return snapshot
    case .unchanged: throw PinnedTestError("expected a loaded snapshot")
    }
}

func createPinnedTestDatabase(home: URL, rows: [PinnedTestDatabaseRow]) throws {
    let url = home.appendingPathComponent("state_5.sqlite")
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw PinnedTestError("could not create SQLite fixture")
    }
    defer { sqlite3_close(database) }
    let schema = """
    CREATE TABLE threads (
      id TEXT PRIMARY KEY, name TEXT, title TEXT, cwd TEXT,
      updated_at INTEGER, is_pinned INTEGER NOT NULL DEFAULT 0
    )
    """
    guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
        throw PinnedTestError("could not create SQLite fixture schema")
    }
    let insert = "INSERT INTO threads (id,name,title,cwd,updated_at,is_pinned) VALUES (?,?,?,?,?,?)"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, insert, -1, &statement, nil) == SQLITE_OK,
          let statement
    else { throw PinnedTestError("could not prepare SQLite fixture insert") }
    defer { sqlite3_finalize(statement) }
    for row in rows {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        bindPinnedTest(row.id, to: statement, index: 1)
        bindPinnedTest(row.name, to: statement, index: 2)
        bindPinnedTest(row.title, to: statement, index: 3)
        bindPinnedTest(row.cwd, to: statement, index: 4)
        sqlite3_bind_int64(statement, 5, row.updatedAt)
        sqlite3_bind_int(statement, 6, row.isPinned ? 1 : 0)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PinnedTestError("could not insert SQLite fixture row")
        }
    }
}

private func bindPinnedTest(_ value: String?, to statement: OpaquePointer, index: Int32) {
    guard let value else {
        sqlite3_bind_null(statement, index)
        return
    }
    _ = value.withCString {
        sqlite3_bind_text(statement, index, $0, -1, pinnedTestSQLiteTransient)
    }
}

func withPinnedTestDirectory<T>(_ operation: (URL) throws -> T) throws -> T {
    let directory = pinnedTestDirectoryURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try operation(directory)
}

func withPinnedTestDirectory<T>(_ operation: (URL) async throws -> T) async throws -> T {
    let directory = pinnedTestDirectoryURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await operation(directory)
}

private func pinnedTestDirectoryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("hyperlite-pinned-tests-\(UUID().uuidString)", isDirectory: true)
}

@MainActor
func waitForPinnedTest(
    attempts: Int = 2_000,
    _ condition: @escaping () async -> Bool
) async throws {
    for _ in 0 ..< attempts {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw PinnedTestError("timed out waiting for asynchronous state")
}

func pinnedTestThread(id: String) -> HyperlitePinnedCodexThread {
    HyperlitePinnedCodexThread(
        id: id, name: nil, title: id, cwd: nil, updatedAt: nil, metadataResolved: true
    )
}

func pinnedTestSignature(_ value: Int64) -> HyperlitePinnedCodexThreadSourceSignature {
    let file = HyperliteCodexFileState.regular(
        inode: UInt64(value), size: value, mode: 0, seconds: value, nanoseconds: value
    )
    return HyperlitePinnedCodexThreadSourceSignature(
        globalState: file, database: .missing, databaseWAL: .missing
    )
}

struct PinnedTestDatabaseRow {
    let id: String
    var name: String?
    var title: String?
    var cwd: String?
    var updatedAt: Int64 = 1
    var isPinned = false
}

struct PinnedTestError: Error {
    let message: String

    init(_ message: String) { self.message = message }
}

actor PinnedTestSequenceClient: HyperlitePinnedCodexThreadClientProtocol {
    private var results: [HyperlitePinnedCodexThreadLoadResult]
    private var observedForces: [Bool] = []

    init(results: [HyperlitePinnedCodexThreadLoadResult]) { self.results = results }

    func load(
        previousSignature: HyperlitePinnedCodexThreadSourceSignature?,
        force: Bool,
        checkedAt: Date
    ) async throws -> HyperlitePinnedCodexThreadLoadResult {
        observedForces.append(force)
        guard !results.isEmpty else { throw PinnedTestError("missing queued result") }
        return results.removeFirst()
    }

    func forces() -> [Bool] { observedForces }
}

actor PinnedTestControlledClient: HyperlitePinnedCodexThreadClientProtocol {
    private var continuations: [CheckedContinuation<HyperlitePinnedCodexThreadLoadResult, Error>] = []

    func load(
        previousSignature: HyperlitePinnedCodexThreadSourceSignature?,
        force: Bool,
        checkedAt: Date
    ) async throws -> HyperlitePinnedCodexThreadLoadResult {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func pendingCount() -> Int { continuations.count }

    func resume(index: Int, with result: HyperlitePinnedCodexThreadLoadResult) {
        continuations[index].resume(returning: result)
    }
}
