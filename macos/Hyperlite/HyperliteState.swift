import Combine
import Foundation

@MainActor
final class HyperliteState: ObservableObject {
    static let shared = HyperliteState()

    @Published private(set) var pullRequestScan: HyperliteProjectPullRequestScan?
    @Published private(set) var configuredProjects: [HyperliteProjectLocation] = []
    @Published private(set) var isRefreshingPullRequests = false
    @Published private(set) var isUpdatingProjects = false
    @Published private(set) var isUpdatingDefaults = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var paletteMode: HyperlitePaletteMode?
    private var pullRequestRefreshTask: Task<Void, Never>?
    private var projectMutationTask: Task<Void, Never>?
    private var defaultsTask: Task<Void, Never>?
    private var pullRequestRefreshGeneration = 0

    var isRefreshing: Bool { isRefreshingPullRequests || isUpdatingDefaults }

    init() {
        refreshPullRequests(mode: .local, continueIfStale: true)
        refreshConfiguredProjects()
    }

    deinit {
        pullRequestRefreshTask?.cancel()
        projectMutationTask?.cancel()
        defaultsTask?.cancel()
    }

    func refresh() {
        forceCacheRefresh()
        refreshConfiguredProjects()
    }

    func forceCacheRefresh() {
        refreshPullRequests(mode: .force, continueIfStale: false, supersedeExisting: true)
    }

    func refreshIfStale(now: Date = Date()) {
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

    func presentError(_ message: String) {
        errorMessage = message
        statusMessage = nil
    }

    func presentStatus(_ message: String?) {
        statusMessage = message
        errorMessage = nil
    }

    func updateConfiguredProject(path: String, action: String) {
        guard !isUpdatingProjects else {
            presentError("A project configuration update is already in progress.")
            return
        }
        isUpdatingProjects = true
        projectMutationTask?.cancel()
        projectMutationTask = Task { [weak self] in
            guard let self else { return }
            do {
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
                presentError(error.localizedDescription)
                isUpdatingProjects = false
                projectMutationTask = nil
            }
        }
    }

    func updateDefaultBranches() {
        guard !isUpdatingDefaults else { return }
        isUpdatingDefaults = true
        defaultsTask?.cancel()
        defaultsTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isUpdatingDefaults = false
                defaultsTask = nil
            }
            do {
                let data = try await HyperliteProcess.run(
                    arguments: ["projects", "update-defaults", "--json"],
                    operation: "update default branches",
                    timeoutSeconds: 600
                )
                let list = try HyperliteJSON.decoder.decode(HyperliteDefaultBranchUpdateList.self, from: data)
                presentStatus(HyperliteGitMaintenance.summary(list.results))
            } catch is CancellationError {
                return
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    func refreshConfiguredProjects() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await HyperliteProcess.run(
                    arguments: ["projects", "list", "--json"],
                    operation: "list projects"
                )
                let list = try HyperliteJSON.decoder.decode(HyperliteConfiguredProjectList.self, from: data)
                configuredProjects = list.projects.map(\.location)
            } catch is CancellationError {
                return
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    func refreshPullRequests(
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
                    waitForEvidence: {}
                ) { decoded in
                    guard self.pullRequestRefreshGeneration == generation else { return }
                    self.pullRequestScan = decoded
                }
            } catch is CancellationError {
                return
            } catch {
                if pullRequestRefreshGeneration == generation {
                    presentError(error.localizedDescription)
                }
            }
        }
    }
}
