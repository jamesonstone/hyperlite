import Combine
import Foundation

@MainActor
final class HyperliteState: ObservableObject {
    static let shared = HyperliteState()

    @Published private(set) var scan: HyperliteWorkScan?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    private var refreshTask: Task<Void, Never>?

    init() { refresh(localOnly: true) }

    deinit { refreshTask?.cancel() }

    func refresh() { refresh(localOnly: false) }

    func items(maxAgeDays: Int, now: Date = Date()) -> [HyperliteWorkItem] {
        guard let scan else { return [] }
        return HyperlitePresentation.items(scan: scan, maxAgeDays: maxAgeDays, now: now)
    }

    func attentionProjectCount(maxAgeDays: Int, now: Date = Date()) -> Int {
        Set(items(maxAgeDays: maxAgeDays, now: now).map(\.repositoryPath)).count
    }

    private func refresh(localOnly: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let arguments = localOnly ? ["--json", "--local", "--no-refresh"] : ["--json"]
                let data = try await Self.runHyperlite(arguments: arguments)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .custom { decoder in
                    let value = try decoder.singleValueContainer().decode(String.self)
                    let fractionalSecondsFormatter = ISO8601DateFormatter()
                    fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = fractionalSecondsFormatter.date(from: value) { return date }
                    let internetDateTimeFormatter = ISO8601DateFormatter()
                    internetDateTimeFormatter.formatOptions = [.withInternetDateTime]
                    if let date = internetDateTimeFormatter.date(from: value) { return date }
                    let container = try decoder.singleValueContainer()
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid ISO-8601 date")
                }
                scan = try decoder.decode(HyperliteWorkScan.self, from: data)
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    private static func runHyperlite(arguments: [String]) async throws -> Data {
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hyperlite-cli")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw HyperliteError.helperMissing }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0 else {
                    let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: HyperliteError.scanFailed(message ?? "hyperlite exited with status \(process.terminationStatus)"))
                    return
                }
                continuation.resume(returning: data)
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

private enum HyperliteError: LocalizedError {
    case helperMissing
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing: "Hyperlite's scan helper is unavailable"
        case let .scanFailed(message): "Hyperlite scan failed: \(message)"
        }
    }
}
