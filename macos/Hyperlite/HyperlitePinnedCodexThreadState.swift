import Combine
import Foundation

@MainActor
final class HyperlitePinnedCodexThreadState: ObservableObject {
    static let shared = HyperlitePinnedCodexThreadState()

    @Published private(set) var snapshot: HyperlitePinnedCodexThreadSnapshot?
    @Published private(set) var lastAvailableAt: Date?
    @Published private(set) var isRefreshing = false

    private let client: any HyperlitePinnedCodexThreadClientProtocol
    private let now: @Sendable () -> Date
    private var sourceSignature: HyperlitePinnedCodexThreadSourceSignature?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        client: any HyperlitePinnedCodexThreadClientProtocol = HyperlitePinnedCodexThreadClient(),
        now: @escaping @Sendable () -> Date = { Date() },
        startImmediately: Bool = true
    ) {
        self.client = client
        self.now = now
        if startImmediately { refresh(force: true) }
    }

    deinit {
        refreshTask?.cancel()
    }

    func refreshIfSourceChanged() {
        refresh(force: false)
    }

    func refresh(force: Bool) {
        if isRefreshing {
            guard force else { return }
            refreshTask?.cancel()
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        let previousSignature = sourceSignature
        let checkedAt = now()
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
                let result = try await client.load(
                    previousSignature: previousSignature,
                    force: force,
                    checkedAt: checkedAt
                )
                guard refreshGeneration == generation else { return }
                switch result {
                case let .unchanged(signature):
                    sourceSignature = signature
                case let .retry(loadedSnapshot):
                    sourceSignature = nil
                    snapshot = loadedSnapshot
                case let .loaded(loadedSnapshot, signature):
                    sourceSignature = signature
                    snapshot = loadedSnapshot
                    if loadedSnapshot.availability != .unavailable {
                        lastAvailableAt = loadedSnapshot.observedAt
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard refreshGeneration == generation else { return }
                sourceSignature = nil
                snapshot = .unavailable(
                    checkedAt: checkedAt,
                    message: "Pinned Codex threads are unavailable"
                )
            }
        }
    }
}
