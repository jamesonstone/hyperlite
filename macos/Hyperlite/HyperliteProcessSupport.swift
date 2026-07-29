import Foundation

final class HyperliteProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var errors = Data()

    func setOutput(_ data: Data) {
        lock.lock()
        output = data
        lock.unlock()
    }

    func setErrors(_ data: Data) {
        lock.lock()
        errors = data
        lock.unlock()
    }

    func values() -> (output: Data, errors: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (output, errors)
    }
}

final class HyperliteRunCompletion: @unchecked Sendable {
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

final class HyperliteProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    private var completion: HyperliteRunCompletion?

    func run(_ process: Process, completion: HyperliteRunCompletion) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else {
            completion.resume(throwing: CancellationError())
            return false
        }
        self.process = process
        self.completion = completion
        do {
            try process.run()
            return true
        } catch {
            self.process = nil
            self.completion = nil
            throw error
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = process
        let completion = completion
        self.process = nil
        self.completion = nil
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
        completion?.resume(throwing: CancellationError())
    }

    func finish() {
        lock.lock()
        process = nil
        completion = nil
        lock.unlock()
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
