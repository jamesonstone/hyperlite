import Combine
import Foundation

@MainActor
final class HyperlitePinboardState: ObservableObject {
    static let shared = HyperlitePinboardState()

    @Published private(set) var snapshot: HyperlitePinboardSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var commandRequest: HyperlitePinboardCommandRequest?

    private let client: any HyperlitePinboardClient
    private var loadTask: Task<Void, Never>?
    private var commandGeneration = 0

    init(client: any HyperlitePinboardClient = HyperliteProcessPinboardClient()) {
        self.client = client
        loadTask = Task { [weak self] in await self?.load() }
    }

    deinit { loadTask?.cancel() }

    func load() async {
        guard !isLoading, !isMutating else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await client.load()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func apply(_ mutation: HyperlitePinboardMutation) async -> HyperlitePinboardSnapshot? {
        guard !isMutating else { return nil }
        await loadTask?.value
        guard snapshot != nil else { return nil }
        isMutating = true
        defer { isMutating = false }
        do {
            let updated = try await client.mutate(mutation)
            snapshot = updated
            errorMessage = nil
            return updated
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func request(_ command: HyperlitePinboardCommand) {
        commandGeneration += 1
        commandRequest = HyperlitePinboardCommandRequest(id: commandGeneration, command: command)
    }

    func consumeRequest(_ id: Int) {
        guard commandRequest?.id == id else { return }
        commandRequest = nil
    }
}
