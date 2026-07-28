import Darwin
import Foundation

enum HyperliteProcess {
    static func run(
        arguments: [String],
        operation: String,
        standardInput: Data? = nil
    ) async throws -> Data {
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hyperlite-cli")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw HyperliteError.helperMissing
        }
        let cancellation = HyperliteProcessCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let output = Pipe()
                let errors = Pipe()
                let input = standardInput == nil ? nil : Pipe()
                let completion = HyperliteRunCompletion(continuation)
                let capture = HyperliteProcessOutput()
                let readers = DispatchGroup()
                readers.enter()
                readers.enter()
                let timeout = DispatchWorkItem {
                    guard process.isRunning, let continuation = completion.takeContinuation() else { return }
                    if process.isRunning { process.terminate() }
                    continuation.resume(throwing: HyperliteError.commandTimedOut(operation))
                }
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = errors
                if let input { process.standardInput = input }
                process.terminationHandler = { process in
                    timeout.cancel()
                    DispatchQueue.global(qos: .utility).async {
                        readers.wait()
                        let captured = capture.values()
                        if process.terminationStatus == 0 {
                            completion.resume(returning: captured.output)
                        } else {
                            let message = String(data: captured.errors, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            completion.resume(throwing: HyperliteError.commandFailed(
                                operation,
                                message ?? "hyperlite exited with status \(process.terminationStatus)"
                            ))
                        }
                        cancellation.finish()
                    }
                }
                do {
                    guard try cancellation.run(process, completion: completion) else { return }
                    startReader(output.fileHandleForReading, readers: readers, capture: capture.setOutput)
                    startReader(errors.fileHandleForReading, readers: readers, capture: capture.setErrors)
                    if let standardInput, let input {
                        DispatchQueue.global(qos: .utility).async {
                            let handle = input.fileHandleForWriting
                            defer { try? handle.close() }
                            guard fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return }
                            try? handle.write(contentsOf: standardInput)
                        }
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + .seconds(60),
                        execute: timeout
                    )
                } catch {
                    timeout.cancel()
                    completion.resume(throwing: error)
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func startReader(
        _ handle: FileHandle,
        readers: DispatchGroup,
        capture: @escaping (Data) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            capture(handle.readDataToEndOfFile())
            readers.leave()
        }
    }
}
