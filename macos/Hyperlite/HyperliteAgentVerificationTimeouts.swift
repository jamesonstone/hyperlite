import Foundation

@MainActor
final class HyperliteAgentVerificationTimeouts {
    private var tasks: [String: Task<Void, Never>] = [:]

    func start(
        _ profile: String,
        timeoutSeconds: UInt64 = HyperliteAgentVerificationPolicy.timeoutSeconds,
        onTimeout: @escaping @MainActor (String) -> Void
    ) {
        finish(profile)
        tasks[profile] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            tasks.removeValue(forKey: profile)
            onTimeout(profile)
        }
    }

    func finish(_ profile: String) {
        tasks.removeValue(forKey: profile)?.cancel()
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
