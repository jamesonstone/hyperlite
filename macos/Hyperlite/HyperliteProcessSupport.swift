import Foundation

final class HyperliteRunCompletion {
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

enum HyperliteError: LocalizedError {
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
