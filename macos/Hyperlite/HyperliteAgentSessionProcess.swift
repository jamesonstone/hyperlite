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
    private var stableTask: Task<Void, Never>?
    private var restartAfterTermination = false

    func start() {
        guard !shouldRun else { return }
        shouldRun = true
        restartCount = 0
        launch()
    }

    func stop() {
        shouldRun = false
        restartAfterTermination = false
        restartTask?.cancel()
        restartTask = nil
        stableTask?.cancel()
        stableTask = nil
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
        onStatus?(.stopped)
    }

    func restart() {
        guard shouldRun else {
            start()
            return
        }
        restartTask?.cancel()
        restartTask = nil
        stableTask?.cancel()
        stableTask = nil
        restartCount = 0
        guard let process else {
            launch()
            return
        }
        restartAfterTermination = true
        onStatus?(.starting)
        output?.fileHandleForReading.readabilityHandler = nil
        errors?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            forceTerminationIfNeeded(process)
        }
    }

    func send<Request: Encodable>(_ request: Request) throws {
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
        let lineBuffer = HyperliteAgentLineBuffer()
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
            for line in lineBuffer.append(data) {
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
            scheduleStableReset(for: process)
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
        stableTask?.cancel()
        stableTask = nil
        process = nil
        input = nil
        output = nil
        errors = nil
        if restartAfterTermination {
            restartAfterTermination = false
            launch()
            return
        }
        guard shouldRun else {
            onStatus?(.stopped)
            return
        }
        scheduleRestart(message: "Agent-session helper exited")
    }

    private func forceTerminationIfNeeded(_ ownedProcess: Process) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if ownedProcess.isRunning {
                kill(ownedProcess.processIdentifier, SIGKILL)
            }
        }
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

    private func scheduleStableReset(for launched: Process) {
        stableTask?.cancel()
        stableTask = Task { [weak self, weak launched] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  let launched,
                  self.process === launched,
                  launched.isRunning
            else { return }
            self.restartCount = 0
        }
    }
}

enum HyperliteAgentProcessError: LocalizedError {
    case unavailable

    var errorDescription: String? { "The live agent response channel is unavailable" }
}
