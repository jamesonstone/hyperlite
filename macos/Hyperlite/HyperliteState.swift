import Combine
import Foundation

@MainActor
final class HyperliteState: ObservableObject {
    static let shared = HyperliteState()

    @Published private(set) var scan: HyperliteThreadScan?
    @Published private(set) var pullRequestScan: HyperliteProjectPullRequestScan?
    @Published private(set) var isRefreshingThreads = false
    @Published private(set) var isRefreshingPullRequests = false
    @Published private(set) var isUpdatingProjects = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var paletteMode: HyperlitePaletteMode?
    @Published private(set) var workspace: HyperliteWorkspace = .dashboard
    private var refreshTask: Task<Void, Never>?
    private var pullRequestRefreshTask: Task<Void, Never>?
    private var projectMutationTask: Task<Void, Never>?
    private var mutationTasks: [String: Task<Void, Never>] = [:]
    private var mutationGenerations: [String: Int] = [:]
    private var refreshGeneration = 0, pullRequestRefreshGeneration = 0

    var isRefreshing: Bool { isRefreshingThreads || isRefreshingPullRequests }

    init() {
        refresh(localOnly: true,
                continueIfRemoteStale: HyperliteFeatureFlags.inferredAttentionPresentation)
        refreshPullRequests(mode: .local, continueIfStale: true)
    }

    deinit {
        refreshTask?.cancel()
        pullRequestRefreshTask?.cancel()
        projectMutationTask?.cancel()
        mutationTasks.values.forEach { $0.cancel() }
    }

    func refresh() {
        refresh(localOnly: !HyperliteFeatureFlags.inferredAttentionPresentation,
                continueIfRemoteStale: false, supersedeExisting: true)
        forceCacheRefresh()
    }

    func forceCacheRefresh() {
        refreshPullRequests(mode: .force, continueIfStale: false, supersedeExisting: true)
    }

    func refreshIfStale(now: Date = Date()) {
        if HyperliteFeatureFlags.inferredAttentionPresentation {
            if !isRefreshingThreads, let scan {
                if HyperlitePresentation.remoteIsStale(scan: scan, now: now) {
                    refresh(localOnly: false, continueIfRemoteStale: false)
                }
            } else if !isRefreshingThreads {
                refresh(localOnly: true, continueIfRemoteStale: true)
            }
        } else if !isRefreshingThreads, scan == nil {
            refresh(localOnly: true, continueIfRemoteStale: false)
        }
        if !isRefreshingPullRequests, let pullRequestScan {
            if HyperlitePullRequestPresentation.isStale(scan: pullRequestScan, now: now) {
                refreshPullRequests(mode: .stale, continueIfStale: false)
            }
        } else if !isRefreshingPullRequests {
            refreshPullRequests(mode: .local, continueIfStale: true)
        }
    }

    func showPalette(_ mode: HyperlitePaletteMode) {
        paletteMode = mode
    }

    func dismissPalette() {
        paletteMode = nil
    }

    func showWorkspace(_ workspace: HyperliteWorkspace) {
        paletteMode = nil
        self.workspace = workspace
    }

    func addProject(path: String) {
        updateConfiguredProject(path: path, action: "add")
    }

    func removeProject(path: String) {
        updateConfiguredProject(path: path, action: "remove")
    }

    func activeThreads() -> [HyperliteThread] {
        guard let scan else { return [] }
        return HyperlitePresentation.activeThreads(scan: scan)
    }

    func attentionThreads() -> [HyperliteThread] {
        guard let scan else { return [] }
        return HyperlitePresentation.attentionThreads(scan: scan)
    }

    func attentionThreadCount() -> Int {
        attentionThreads().count
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
        let previous = mutationTasks[requestID]
        let generation = (mutationGenerations[requestID] ?? 0) + 1
        mutationGenerations[requestID] = generation
        previous?.cancel()
        mutationTasks[requestID] = Task { [weak self] in
            guard let self else { return }
            do {
                await previous?.value
                try Task.checkCancellation()
                try await waitForRefresh()
                _ = try await HyperliteProcess.run(
                    arguments: ["thread", "note", threadID, "--stdin"],
                    operation: "save note",
                    standardInput: Data(note.utf8)
                )
                guard finishMutation(requestID, generation: generation) else { return }
                refresh(localOnly: true, continueIfRemoteStale: false)
            } catch is CancellationError {
                _ = finishMutation(requestID, generation: generation)
            } catch {
                if finishMutation(requestID, generation: generation) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func finishMutation(_ requestID: String, generation: Int) -> Bool {
        guard mutationGenerations[requestID] == generation else { return false }
        mutationTasks[requestID] = nil
        mutationGenerations[requestID] = nil
        return true
    }

    private func waitForRefresh() async throws {
        try Task.checkCancellation()
        await refreshTask?.value
        try Task.checkCancellation()
    }

    private func updateConfiguredProject(path: String, action: String) {
        guard !isUpdatingProjects else {
            errorMessage = "A project configuration update is already in progress."
            return
        }
        isUpdatingProjects = true
        projectMutationTask?.cancel()
        projectMutationTask = Task { [weak self] in
            guard let self else { return }
            do {
                await refreshTask?.value
                await pullRequestRefreshTask?.value
                try Task.checkCancellation()
                _ = try await HyperliteProcess.run(
                    arguments: ["projects", action, path],
                    operation: "\(action) project"
                )
                isUpdatingProjects = false
                projectMutationTask = nil
                refresh()
            } catch is CancellationError {
                isUpdatingProjects = false
                projectMutationTask = nil
            } catch {
                errorMessage = error.localizedDescription
                isUpdatingProjects = false
                projectMutationTask = nil
            }
        }
    }

    private func refreshPullRequests(
        mode: HyperlitePullRequestRefreshMode,
        continueIfStale: Bool,
        supersedeExisting: Bool = false
    ) {
        if isRefreshingPullRequests {
            guard supersedeExisting else { return }
            pullRequestRefreshTask?.cancel()
        }
        pullRequestRefreshGeneration += 1
        let generation = pullRequestRefreshGeneration
        isRefreshingPullRequests = true
        pullRequestRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if pullRequestRefreshGeneration == generation {
                    isRefreshingPullRequests = false
                    pullRequestRefreshTask = nil
                }
            }
            do {
                try await HyperlitePullRequestRefresh.run(
                    mode: mode,
                    continueIfStale: continueIfStale,
                    // Serializing these helpers avoids a user-triggered burst
                    // when attention evidence is enabled again.
                    waitForEvidence: self.waitForRefresh
                ) { decoded in
                    guard self.pullRequestRefreshGeneration == generation else { return }
                    self.pullRequestScan = decoded
                }
            } catch is CancellationError {
                return
            } catch {
                if pullRequestRefreshGeneration == generation {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func refresh(
        localOnly: Bool,
        continueIfRemoteStale: Bool,
        supersedeExisting: Bool = false
    ) {
        if isRefreshingThreads {
            guard supersedeExisting else { return }
            refreshTask?.cancel()
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshingThreads = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if refreshGeneration == generation {
                    isRefreshingThreads = false
                    refreshTask = nil
                }
            }
            do {
                var decoded = try await runScan(localOnly: localOnly)
                guard refreshGeneration == generation else { return }
                scan = decoded
                errorMessage = nil
                if localOnly, continueIfRemoteStale,
                   HyperlitePresentation.remoteIsStale(scan: decoded, now: Date())
                {
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
        return try HyperliteJSON.decoder.decode(HyperliteThreadScan.self, from: data)
    }

    private func enrichIfMateriallyChanged(
        from deterministic: HyperliteThreadScan,
        generation: Int
    ) async {
        do {
            let data = try await HyperliteProcess.run(arguments: ["infer", "--json"], operation: "inference")
            guard refreshGeneration == generation else { return }
            let enriched = try HyperliteJSON.decoder.decode(HyperliteThreadScan.self, from: data)
            if HyperlitePresentation.coordinationProjection(enriched) !=
                HyperlitePresentation.coordinationProjection(deterministic)
            {
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
}
