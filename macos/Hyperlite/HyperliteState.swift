import Combine
import Foundation

@MainActor
final class HyperliteState: ObservableObject {
    static let shared = HyperliteState()

    @Published private(set) var scan: HyperliteThreadScan?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPruning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var paletteMode: HyperlitePaletteMode?
    private var refreshTask: Task<Void, Never>?
    private var pruneTask: Task<Void, Never>?
    private var mutationTasks: [String: Task<Void, Never>] = [:]
    private var requestedSeenRevisions: Set<String> = []

    init() { refresh(localOnly: true, continueIfRemoteStale: true) }

    deinit {
        refreshTask?.cancel()
        pruneTask?.cancel()
        mutationTasks.values.forEach { $0.cancel() }
    }

    func refresh() { refresh(localOnly: false, continueIfRemoteStale: false) }

    func refreshIfStale(now: Date = Date()) {
        guard !isRefreshing else { return }
        guard let scan else {
            refresh(localOnly: true, continueIfRemoteStale: true)
            return
        }
        if remoteIsStale(scan: scan, now: now) {
            refresh()
        }
    }

    func showPalette(_ mode: HyperlitePaletteMode) {
        paletteMode = mode
    }

    func dismissPalette() {
        paletteMode = nil
    }

    func prune(_ diagnostic: HyperliteDiagnostic) {
        guard !isPruning, !isRefreshing,
              diagnostic.isPrunableWorktree,
              let repositoryPath = diagnostic.repositoryPath,
              let worktreePath = diagnostic.worktreePath
        else { return }
        isPruning = true
        pruneTask?.cancel()
        pruneTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await Self.runHyperlite(
                    arguments: ["prune-worktree", repositoryPath, worktreePath],
                    operation: "prune"
                )
                isPruning = false
                refresh(localOnly: true, continueIfRemoteStale: false)
            } catch is CancellationError {
                isPruning = false
            } catch {
                errorMessage = error.localizedDescription
                isPruning = false
            }
        }
    }

    func visibleThreads(maxAgeDays: Int, now: Date = Date()) -> [HyperliteThread] {
        guard let scan else { return [] }
        return HyperlitePresentation.visibleThreads(scan: scan, maxAgeDays: maxAgeDays, now: now)
    }

    func threads(
        section: HyperliteThreadSection,
        maxAgeDays: Int,
        now: Date = Date()
    ) -> [HyperliteThread] {
        guard let scan else { return [] }
        return HyperlitePresentation.threads(scan: scan, section: section, maxAgeDays: maxAgeDays, now: now)
    }

    func attentionThreadCount(maxAgeDays: Int, now: Date = Date()) -> Int {
        threads(section: .attention, maxAgeDays: maxAgeDays, now: now).count
    }

    func markSeen(_ thread: HyperliteThread) {
        guard thread.hasUnseenAttention, !thread.latestMaterialRevision.isEmpty else { return }
        let requestID = "\(thread.id)@\(thread.latestMaterialRevision)"
        guard requestedSeenRevisions.insert(requestID).inserted else { return }
        mutationTasks[requestID]?.cancel()
        mutationTasks[requestID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await waitForRefresh()
                _ = try await Self.runHyperlite(
                    arguments: ["thread", "seen", thread.id, "--revision", thread.latestMaterialRevision],
                    operation: "mark seen"
                )
                requestedSeenRevisions.remove(requestID)
                mutationTasks[requestID] = nil
                refresh(localOnly: true, continueIfRemoteStale: false)
            } catch is CancellationError {
                requestedSeenRevisions.remove(requestID)
                mutationTasks[requestID] = nil
            } catch {
                requestedSeenRevisions.remove(requestID)
                mutationTasks[requestID] = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateNote(threadID: String, note: String) {
        let requestID = "note:\(threadID)"
        mutationTasks[requestID]?.cancel()
        mutationTasks[requestID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await waitForRefresh()
                _ = try await Self.runHyperlite(
                    arguments: ["thread", "note", threadID, "--stdin"],
                    operation: "save note",
                    standardInput: Data(note.utf8)
                )
                mutationTasks[requestID] = nil
                refresh(localOnly: true, continueIfRemoteStale: false)
            } catch is CancellationError {
                mutationTasks[requestID] = nil
            } catch {
                mutationTasks[requestID] = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func waitForRefresh() async throws {
        while isRefreshing {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func refresh(localOnly: Bool, continueIfRemoteStale: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                var decoded = try await scan(localOnly: localOnly)
                scan = decoded
                errorMessage = nil
                if localOnly, continueIfRemoteStale, remoteIsStale(scan: decoded, now: Date()) {
                    decoded = try await scan(localOnly: false)
                    scan = decoded
                }
                if !localOnly || continueIfRemoteStale {
                    await enrichIfMateriallyChanged(from: decoded)
                }
            } catch is CancellationError {
                isRefreshing = false
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    private func scan(localOnly: Bool) async throws -> HyperliteThreadScan {
        let arguments = localOnly ? ["--json", "--local", "--no-refresh"] : ["--json"]
        let data = try await Self.runHyperlite(arguments: arguments, operation: "scan")
        return try Self.decoder.decode(HyperliteThreadScan.self, from: data)
    }

    private func enrichIfMateriallyChanged(from deterministic: HyperliteThreadScan) async {
        do {
            let data = try await Self.runHyperlite(arguments: ["infer", "--json"], operation: "inference")
            let enriched = try Self.decoder.decode(HyperliteThreadScan.self, from: data)
            if coordinationProjection(enriched) != coordinationProjection(deterministic) {
                scan = enriched
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remoteIsStale(scan: HyperliteThreadScan, now: Date) -> Bool {
        guard let observedAt = scan.remoteObservedAt else { return true }
        let interval = max(1, scan.remoteRefreshIntervalSeconds ?? 300)
        return now.timeIntervalSince(observedAt) >= Double(interval)
    }

    private func coordinationProjection(_ scan: HyperliteThreadScan) -> String {
        scan.threads.map { thread in
            let dependencies = thread.dependencies.map { "\($0.kind):\($0.targetThreadID ?? $0.target)" }.joined(separator: ",")
            let implications = thread.implications.map(\.summary).joined(separator: ",")
            let obligations = thread.remainingObligations.map(\.summary).joined(separator: ",")
            return [
                thread.id, thread.latestMaterialRevision, thread.phase.rawValue,
                thread.goal, thread.rationale, dependencies, implications, obligations,
                thread.whyNow, thread.inferenceStatus,
            ].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
            let container = try decoder.singleValueContainer()
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid ISO-8601 date")
        }
        return decoder
    }()

    private static func runHyperlite(
        arguments: [String],
        operation: String,
        standardInput: Data? = nil
    ) async throws -> Data {
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hyperlite-cli")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw HyperliteError.helperMissing
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            let input = standardInput == nil ? nil : Pipe()
            let completion = HyperliteRunCompletion(continuation)
            let timeout = DispatchWorkItem {
                guard process.isRunning, let continuation = completion.takeContinuation() else { return }
                if process.isRunning { process.terminate() }
                continuation.resume(throwing: HyperliteError.commandTimedOut(operation))
            }
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            if let input { process.standardInput = input }
            process.terminationHandler = { process in
                timeout.cancel()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0 else {
                    let message = String(
                        data: errors.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    )?.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion.resume(throwing: HyperliteError.commandFailed(
                        operation,
                        message ?? "hyperlite exited with status \(process.terminationStatus)"
                    ))
                    return
                }
                completion.resume(returning: data)
            }
            do {
                try process.run()
                if let standardInput, let input {
                    input.fileHandleForWriting.write(standardInput)
                    try? input.fileHandleForWriting.close()
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(60), execute: timeout)
            } catch {
                timeout.cancel()
                completion.resume(throwing: error)
            }
        }
    }
}

private final class HyperliteRunCompletion {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    init(_ continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func resume(returning data: Data) {
        takeContinuation()?.resume(returning: data)
    }

    func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    func takeContinuation() -> CheckedContinuation<Data, Error>? {
        lock.lock()
        defer { lock.unlock() }
        defer { continuation = nil }
        return continuation
    }
}

private enum HyperliteError: LocalizedError {
    case helperMissing
    case commandFailed(String, String)
    case commandTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing: "Hyperlite's scan helper is unavailable"
        case let .commandFailed(operation, message): "Hyperlite \(operation) failed: \(message)"
        case let .commandTimedOut(operation): "Hyperlite \(operation) timed out"
        }
    }
}
