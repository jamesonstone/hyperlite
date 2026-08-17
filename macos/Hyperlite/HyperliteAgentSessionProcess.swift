import Darwin
import Foundation

@MainActor
final class HyperliteAgentSessionProcess {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case unavailable(String)
    }

    var onRecord: ((HyperliteAgentWireRecord) -> Void)?
    var onStatus: ((Status) -> Void)?

    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var errors: Pipe?
    private var shouldRun = false
    private var restartCount = 0
    private var restartTask: Task<Void, Never>?
    private let lineBuffer = HyperliteAgentLineBuffer()

    func start() {
        guard !shouldRun else { return }
        shouldRun = true
        restartCount = 0
        launch()
    }

    func stop() {
        shouldRun = false
        restartTask?.cancel()
        restartTask = nil
        guard let process else {
            onStatus?(.stopped)
            return
        }
        output?.fileHandleForReading.readabilityHandler = nil
        errors?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let ownedProcess = process
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if ownedProcess.isRunning {
                    kill(ownedProcess.processIdentifier, SIGKILL)
                }
            }
        }
        self.process = nil
        input = nil
        output = nil
        errors = nil
        lineBuffer.reset()
        onStatus?(.stopped)
    }

    func send(_ request: HyperliteAgentActionRequest) throws {
        guard let handle = input?.fileHandleForWriting, process?.isRunning == true else {
            throw HyperliteAgentProcessError.unavailable
        }
        let encoder = JSONEncoder()
        var data = try encoder.encode(request)
        data.append(0x0A)
        guard fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw HyperliteAgentProcessError.unavailable
        }
        try handle.write(contentsOf: data)
    }

    private func launch() {
        guard shouldRun else { return }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hyperlite-cli")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            onStatus?(.unavailable("Agent-session helper is unavailable"))
            shouldRun = false
            return
        }
        onStatus?(.starting)
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = ["agent", "sessions", "serve"]
        process.environment = HyperliteProcessEnvironment.inheriting(ProcessInfo.processInfo.environment)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in self?.didTerminate(process) }
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in self?.lineBuffer.append(data) ?? [] {
                guard line.count <= 1_048_576,
                      let record = try? HyperliteAgentWireRecord.decode(line)
                else { continue }
                Task { @MainActor in self?.onRecord?(record) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        do {
            try process.run()
            self.process = process
            self.input = input
            self.output = output
            self.errors = errors
            onStatus?(.running)
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            scheduleRestart(message: "Agent-session helper could not start")
        }
    }

    private func didTerminate(_ terminated: Process) {
        guard process === terminated else { return }
        output?.fileHandleForReading.readabilityHandler = nil
        errors?.fileHandleForReading.readabilityHandler = nil
        process = nil
        input = nil
        output = nil
        errors = nil
        lineBuffer.reset()
        guard shouldRun else {
            onStatus?(.stopped)
            return
        }
        scheduleRestart(message: "Agent-session helper exited")
    }

    private func scheduleRestart(message: String) {
        guard shouldRun, restartCount < 3 else {
            shouldRun = false
            onStatus?(.unavailable(message))
            return
        }
        let delay = 1 << restartCount
        restartCount += 1
        onStatus?(.starting)
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.launch()
        }
    }
}

private final class HyperliteAgentLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ incoming: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        data.append(incoming)
        if data.count > 2_097_152 { data.removeAll(keepingCapacity: false); return [] }
        var lines: [Data] = []
        while let newline = data.firstIndex(of: 0x0A) {
            let line = Data(data[..<newline])
            data.removeSubrange(data.startIndex ... newline)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    func reset() {
        lock.lock()
        data.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}

enum HyperliteAgentProcessError: LocalizedError {
    case unavailable

    var errorDescription: String? { "The live agent response channel is unavailable" }
}
