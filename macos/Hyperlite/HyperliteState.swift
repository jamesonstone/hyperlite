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
    private var refreshGeneration = 0

    init() { refresh(localOnly: true, continueIfRemoteStale: true) }

    deinit {
        refreshTask?.cancel()
        pruneTask?.cancel()
        mutationTasks.values.forEach { $0.cancel() }
    }

    func refresh() {
        refresh(localOnly: false, continueIfRemoteStale: false, supersedeExisting: true)
    }

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
                _ = try await HyperliteProcess.run(
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

    func markSeen(threadID: String) {
        let requestID = "seen:\(threadID)"
        guard mutationTasks[requestID] == nil else { return }
        mutationTasks[requestID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await waitForRefresh()
                guard let thread = scan?.threads.first(where: { $0.id == threadID }),
                      thread.hasUnseenAttention,
                      !thread.latestMaterialRevision.isEmpty
                else {
                    mutationTasks[requestID] = nil
                    return
                }
                _ = try await HyperliteProcess.run(
                    arguments: ["thread", "seen", thread.id, "--revision", thread.latestMaterialRevision],
                    operation: "mark seen"
                )
                mutationTasks[requestID] = nil
                refresh(localOnly: true, continueIfRemoteStale: false)
            } catch is CancellationError {
                mutationTasks[requestID] = nil
            } catch {
                mutationTasks[requestID] = nil
                if error.localizedDescription.contains("advanced; refresh before marking it seen") {
                    refresh(localOnly: true, continueIfRemoteStale: false)
                } else {
                    errorMessage = error.localizedDescription
                }
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
                _ = try await HyperliteProcess.run(
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
        try Task.checkCancellation()
        await refreshTask?.value
        try Task.checkCancellation()
    }

    private func refresh(
        localOnly: Bool,
        continueIfRemoteStale: Bool,
        supersedeExisting: Bool = false
    ) {
        if isRefreshing {
            guard supersedeExisting else { return }
            refreshTask?.cancel()
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if refreshGeneration == generation {
                    isRefreshing = false
                    refreshTask = nil
                }
            }
            do {
                var decoded = try await runScan(localOnly: localOnly)
                guard refreshGeneration == generation else { return }
                scan = decoded
                errorMessage = nil
                if localOnly, continueIfRemoteStale, remoteIsStale(scan: decoded, now: Date()) {
                    decoded = try await runScan(localOnly: false)
                    guard refreshGeneration == generation else { return }
                    scan = decoded
                }
                if !localOnly || continueIfRemoteStale {
                    await enrichIfMateriallyChanged(from: decoded, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                if refreshGeneration == generation {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func runScan(localOnly: Bool) async throws -> HyperliteThreadScan {
        let arguments = localOnly ? ["--json", "--local", "--no-refresh"] : ["--json"]
        let data = try await HyperliteProcess.run(arguments: arguments, operation: "scan")
        return try Self.decoder.decode(HyperliteThreadScan.self, from: data)
    }

    private func enrichIfMateriallyChanged(
        from deterministic: HyperliteThreadScan,
        generation: Int
    ) async {
        do {
            let data = try await HyperliteProcess.run(arguments: ["infer", "--json"], operation: "inference")
            guard refreshGeneration == generation else { return }
            let enriched = try Self.decoder.decode(HyperliteThreadScan.self, from: data)
            if coordinationProjection(enriched) != coordinationProjection(deterministic) {
                scan = enriched
            }
        } catch is CancellationError {
            return
        } catch {
            if refreshGeneration == generation {
                errorMessage = error.localizedDescription
            }
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
            if let date = try? fractionalDateFormat.parse(value) { return date }
            if let date = try? standardDateFormat.parse(value) { return date }
            let container = try decoder.singleValueContainer()
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid ISO-8601 date")
        }
        return decoder
    }()

    nonisolated private static let fractionalDateFormat = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true
    )
    nonisolated private static let standardDateFormat = Date.ISO8601FormatStyle()
}
