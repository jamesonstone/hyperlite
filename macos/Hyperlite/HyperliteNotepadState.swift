import Combine
import Foundation

protocol HyperliteNotepadClient: Sendable {
    func load() async throws -> String
    func save(_ content: String) async throws
}

struct HyperliteProcessNotepadClient: HyperliteNotepadClient {
    func load() async throws -> String {
        let data = try await HyperliteProcess.run(
            arguments: ["notepad", "show"],
            operation: "load notepad"
        )
        guard let content = String(data: data, encoding: .utf8) else {
            throw HyperliteNotepadError.invalidUTF8
        }
        return content
    }

    func save(_ content: String) async throws {
        _ = try await HyperliteProcess.run(
            arguments: ["notepad", "set", "--stdin"],
            operation: "save notepad",
            standardInput: Data(content.utf8)
        )
    }
}

@MainActor
final class HyperliteNotepadState: ObservableObject {
    static let shared = HyperliteNotepadState()
    nonisolated static let maxBytes = 256 * 1024
    nonisolated static let autosaveDelay: Duration = .seconds(3)

    @Published private(set) var text = ""
    @Published private(set) var isLoaded = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    var isDirty: Bool { text != savedText }

    private let client: any HyperliteNotepadClient
    private let autosaveDelay: Duration
    private var savedText = ""
    private var hasLocalEdits = false
    private var loadTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var saveQueued = false

    init(
        client: any HyperliteNotepadClient = HyperliteProcessNotepadClient(),
        autosaveDelay: Duration = HyperliteNotepadState.autosaveDelay,
        loadImmediately: Bool = true
    ) {
        self.client = client
        self.autosaveDelay = autosaveDelay
        if loadImmediately {
            loadTask = Task { [weak self] in
                await self?.load()
            }
        }
    }

    deinit {
        loadTask?.cancel()
        autosaveTask?.cancel()
        saveTask?.cancel()
    }

    @discardableResult
    func update(_ candidate: String, byteCount: Int? = nil) -> Bool {
        guard (byteCount ?? candidate.utf8.count) <= Self.maxBytes else {
            errorMessage = HyperliteNotepadError.tooLarge.localizedDescription
            return false
        }
        guard candidate != text else { return true }
        text = candidate
        hasLocalEdits = true
        if isLoaded {
            scheduleAutosave()
        }
        return true
    }

    func waitUntilLoaded() async {
        await loadTask?.value
    }

    @discardableResult
    func flush() async -> Bool {
        autosaveTask?.cancel()
        autosaveTask = nil
        await loadTask?.value
        autosaveTask?.cancel()
        autosaveTask = nil
        await saveTask?.value
        if isDirty {
            requestSave()
            await saveTask?.value
        }
        return !isDirty && errorMessage == nil
    }

    private func load() async {
        defer {
            isLoaded = true
            loadTask = nil
            if isDirty {
                scheduleAutosave()
            }
        }
        do {
            let persisted = try await client.load()
            guard persisted.utf8.count <= Self.maxBytes else {
                throw HyperliteNotepadError.tooLarge
            }
            savedText = persisted
            if !hasLocalEdits {
                text = persisted
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard isDirty else {
            autosaveTask = nil
            return
        }
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.autosaveTask = nil
            self?.requestSave()
        }
    }

    private func requestSave() {
        guard isLoaded, isDirty else { return }
        guard saveTask == nil else {
            saveQueued = true
            return
        }
        let candidate = text
        let client = client
        isSaving = true
        saveTask = Task { [weak self] in
            do {
                try await client.save(candidate)
                self?.finishSave(candidate: candidate, error: nil)
            } catch is CancellationError {
                self?.finishSave(candidate: candidate, error: nil, cancelled: true)
            } catch {
                self?.finishSave(candidate: candidate, error: error)
            }
        }
    }

    private func finishSave(
        candidate: String,
        error: Error?,
        cancelled: Bool = false
    ) {
        if error == nil, !cancelled {
            savedText = candidate
            errorMessage = nil
        } else if let error {
            errorMessage = error.localizedDescription
        }
        isSaving = false
        saveTask = nil
        let shouldContinue = saveQueued && isDirty && !cancelled
        saveQueued = false
        if shouldContinue {
            requestSave()
        }
    }
}

private enum HyperliteNotepadError: LocalizedError {
    case invalidUTF8
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidUTF8: "Hyperlite's notepad is not valid UTF-8"
        case .tooLarge: "Notepad is limited to 256 KiB"
        }
    }
}
