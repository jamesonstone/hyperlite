import Darwin
import Foundation
import SQLite3

private let hyperliteSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

protocol HyperlitePinnedCodexThreadClientProtocol: Sendable {
    func load(
        previousSignature: HyperlitePinnedCodexThreadSourceSignature?,
        force: Bool,
        checkedAt: Date
    ) async throws -> HyperlitePinnedCodexThreadLoadResult
}

struct HyperlitePinnedCodexThreadClient: HyperlitePinnedCodexThreadClientProtocol, @unchecked Sendable {
    static let maxGlobalStateBytes = 16 * 1024 * 1024
    static let maxPinnedThreadCount = 10_000

    typealias DataLoader = @Sendable (URL, Int) throws -> Data

    private let environment: [String: String]
    private let defaultHome: URL
    private let dataLoader: DataLoader

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        dataLoader: @escaping DataLoader = { url, limit in
            try HyperlitePinnedCodexThreadClient.readBoundedFile(url, limit: limit)
        }
    ) {
        self.environment = environment
        self.defaultHome = defaultHome
        self.dataLoader = dataLoader
    }

    func load(
        previousSignature: HyperlitePinnedCodexThreadSourceSignature?,
        force: Bool,
        checkedAt: Date
    ) async throws -> HyperlitePinnedCodexThreadLoadResult {
        let operation = Task.detached(priority: .utility) {
            try loadSynchronously(
                previousSignature: previousSignature,
                force: force,
                checkedAt: checkedAt
            )
        }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    static func resolveCodexHome(
        environment: [String: String],
        defaultHome: URL
    ) -> URL {
        if let value = environment["CODEX_HOME"],
           !value.isEmpty,
           (value as NSString).isAbsolutePath
        {
            let candidate = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                return candidate
            }
        }
        return defaultHome.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL
    }

    static func readBoundedFile(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw HyperlitePinnedCodexMembershipError.globalStateTooLarge }
        return data
    }

    private func loadSynchronously(
        previousSignature: HyperlitePinnedCodexThreadSourceSignature?,
        force: Bool,
        checkedAt: Date
    ) throws -> HyperlitePinnedCodexThreadLoadResult {
        let home = Self.resolveCodexHome(environment: environment, defaultHome: defaultHome)
        let initial = sourceSignature(home: home)
        if !force, previousSignature == initial { return .unchanged(initial) }

        var before = initial
        for attempt in 0 ..< 2 {
            try Task.checkCancellation()
            let snapshot = try snapshot(home: home, checkedAt: checkedAt)
            let after = sourceSignature(home: home)
            if before == after { return .loaded(snapshot, after) }
            if attempt == 0 {
                before = after
                continue
            }
            return .loaded(
                .unavailable(
                    checkedAt: checkedAt,
                    message: "Codex pinned-thread state changed during refresh"
                ),
                before
            )
        }
        preconditionFailure("bounded refresh loop must return")
    }

    private func snapshot(
        home: URL,
        checkedAt: Date
    ) throws -> HyperlitePinnedCodexThreadSnapshot {
        let globalState = home.appendingPathComponent(".codex-global-state.json")
        switch fileState(globalState) {
        case .missing:
            return .unavailable(checkedAt: checkedAt, message: "Codex pinned-thread state is missing")
        case .other, .unreadable:
            return .unavailable(checkedAt: checkedAt, message: "Codex pinned-thread state is unreadable")
        case let .regular(_, size, _, _, _):
            guard size <= Int64(Self.maxGlobalStateBytes) else {
                return .unavailable(
                    checkedAt: checkedAt,
                    message: "Codex pinned-thread state exceeds the safety limit"
                )
            }
        }

        let pinnedIDs: [String]
        do {
            let data = try dataLoader(globalState, Self.maxGlobalStateBytes)
            pinnedIDs = try decodePinnedIDs(data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HyperlitePinnedCodexMembershipError {
            return .unavailable(checkedAt: checkedAt, message: error.message)
        } catch {
            return .unavailable(checkedAt: checkedAt, message: "Codex pinned-thread state is unreadable")
        }

        guard pinnedIDs.count <= Self.maxPinnedThreadCount else {
            return .unavailable(
                checkedAt: checkedAt,
                message: "Codex pinned-thread list exceeds the safety limit"
            )
        }
        guard pinnedIDs.allSatisfy({ !$0.isEmpty }) else {
            return .unavailable(checkedAt: checkedAt, message: "Codex pinned-thread list is malformed")
        }

        var seen = Set<String>()
        let orderedIDs = pinnedIDs.filter { seen.insert($0).inserted }
        guard !orderedIDs.isEmpty else { return .current(threads: [], observedAt: checkedAt) }

        let database = home.appendingPathComponent("state_5.sqlite")
        let metadata = try loadMetadata(database: database, ids: orderedIDs)
        var unresolved = 0
        let threads = orderedIDs.map { id in
            let row = metadata?[id]
            let resolved = row?.hasUsableTitle == true
            if !resolved { unresolved += 1 }
            return HyperlitePinnedCodexThread(
                id: id,
                name: row?.name,
                title: row?.title,
                cwd: row?.cwd,
                updatedAt: row?.updatedAt,
                metadataResolved: resolved
            )
        }
        if unresolved > 0 {
            return .partial(
                threads: threads,
                unresolvedMetadataCount: unresolved,
                observedAt: checkedAt
            )
        }
        return .current(threads: threads, observedAt: checkedAt)
    }

    private func decodePinnedIDs(_ data: Data) throws -> [String] {
        do {
            return try JSONDecoder().decode(HyperlitePinnedCodexGlobalState.self, from: data)
                .pinnedThreadIDs
        } catch let error as HyperlitePinnedCodexMembershipError {
            throw error
        } catch {
            throw HyperlitePinnedCodexMembershipError.globalStateMalformed
        }
    }

    private func loadMetadata(
        database: URL,
        ids: [String]
    ) throws -> [String: HyperlitePinnedCodexThreadMetadata]? {
        guard case .regular = fileState(database) else { return nil }
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard database.path.withCString({ sqlite3_open_v2($0, &connection, flags, nil) }) == SQLITE_OK,
              let connection
        else {
            if let connection { sqlite3_close(connection) }
            return nil
        }
        defer { sqlite3_close(connection) }
        sqlite3_busy_timeout(connection, 500)
        guard sqlite3_exec(connection, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
            return nil
        }

        let query = "SELECT id, name, title, cwd, updated_at FROM threads WHERE id = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return nil }
        defer { sqlite3_finalize(statement) }

        var result: [String: HyperlitePinnedCodexThreadMetadata] = [:]
        for id in ids {
            try Task.checkCancellation()
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            let bound = id.withCString {
                sqlite3_bind_text(statement, 1, $0, -1, hyperliteSQLiteTransient)
            }
            guard bound == SQLITE_OK else { return nil }
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                result[id] = HyperlitePinnedCodexThreadMetadata(
                    name: columnString(statement, index: 1),
                    title: columnString(statement, index: 2),
                    cwd: columnString(statement, index: 3),
                    updatedAt: columnDate(statement, index: 4)
                )
            case SQLITE_DONE:
                continue
            default:
                return nil
            }
        }
        return result
    }

    private func sourceSignature(home: URL) -> HyperlitePinnedCodexThreadSourceSignature {
        let database = home.appendingPathComponent("state_5.sqlite")
        return HyperlitePinnedCodexThreadSourceSignature(
            globalState: fileState(home.appendingPathComponent(".codex-global-state.json")),
            database: fileState(database),
            databaseWAL: fileState(URL(fileURLWithPath: database.path + "-wal"))
        )
    }

    private func fileState(_ url: URL) -> HyperliteCodexFileState {
        var value = stat()
        let status = url.path.withCString { Darwin.lstat($0, &value) }
        guard status == 0 else {
            return errno == ENOENT || errno == ENOTDIR ? .missing : .unreadable
        }
        guard value.st_mode & S_IFMT == S_IFREG else { return .other }
        return .regular(
            inode: UInt64(value.st_ino),
            size: Int64(value.st_size),
            mode: UInt32(value.st_mode),
            seconds: Int64(value.st_mtimespec.tv_sec),
            nanoseconds: Int64(value.st_mtimespec.tv_nsec)
        )
    }

    private func columnString(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index)
        else { return nil }
        let text = String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func columnDate(_ statement: OpaquePointer, index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let timestamp = sqlite3_column_int64(statement, index)
        return timestamp > 0 ? Date(timeIntervalSince1970: TimeInterval(timestamp)) : nil
    }

}
