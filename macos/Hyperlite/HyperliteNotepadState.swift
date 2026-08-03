import Combine
import Foundation

@MainActor
final class HyperliteNotepadState: ObservableObject {
    static let shared = HyperliteNotepadState()
    nonisolated static let maxBytes = 256 * 1024
    nonisolated static let autosaveDelay: Duration = .seconds(3)

    @Published private(set) var pinnedText = ""
    @Published private(set) var dailyText = ""
    @Published private(set) var selectedDate: Date
    @Published private(set) var activeTab: HyperliteNotepadTab = .daily
    @Published private(set) var isLoaded = false
    @Published private(set) var isIndexReady = false
    @Published private(set) var searchIndexRevision = 0
    @Published var isSaving = false
    @Published private(set) var isNavigating = false
    @Published var errorMessage: String?
    @Published private(set) var focusRequest: HyperliteNotepadFocusRequest?

    var selectedDateIdentifier: String {
        HyperliteNoteDate.identifier(for: selectedDate, calendar: calendar)
    }

    var isDirty: Bool { pinnedText != savedPinnedText || dailyText != savedDailyText }

    let client: any HyperliteNotepadClient
    private let searchIndex: HyperliteNoteSearchIndex
    let autosaveDelay: Duration
    private var calendar: Calendar
    private let now: @Sendable () -> Date
    var savedPinnedText = ""
    var savedDailyText = ""
    private var hasPinnedLocalEdits = false
    private var hasDailyLocalEdits = false
    private var loadTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var indexUpdateTask: Task<Void, Never>?
    private var pendingIndexDocuments: [HyperliteNoteID: HyperliteNoteDocument] = [:]
    private var indexErrorMessage: String?
    var autosaveTasks: [HyperliteNoteID: Task<Void, Never>] = [:]
    var saveTasks: [HyperliteNoteID: Task<Void, Never>] = [:]
    var saveQueued: Set<HyperliteNoteID> = []
    private var focusGeneration = 0

    init(
        client: any HyperliteNotepadClient = HyperliteProcessNotepadClient(),
        searchIndex: HyperliteNoteSearchIndex = HyperliteNoteSearchIndex(),
        autosaveDelay: Duration = HyperliteNotepadState.autosaveDelay,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() },
        loadImmediately: Bool = true
    ) {
        self.client = client
        self.searchIndex = searchIndex
        self.autosaveDelay = autosaveDelay
        self.calendar = calendar
        self.now = now
        selectedDate = calendar.startOfDay(for: now())
        if loadImmediately {
            loadTask = Task { [weak self] in await self?.loadInitialDocuments() }
            indexTask = Task { [weak self] in await self?.buildSearchIndex() }
        }
    }

    deinit {
        loadTask?.cancel()
        indexTask?.cancel()
        indexUpdateTask?.cancel()
        autosaveTasks.values.forEach { $0.cancel() }
        saveTasks.values.forEach { $0.cancel() }
    }

    @discardableResult
    func updatePinned(_ candidate: String, byteCount: Int? = nil) -> Bool {
        guard valid(candidate, byteCount: byteCount) else { return false }
        guard candidate != pinnedText else { return true }
        pinnedText = candidate
        hasPinnedLocalEdits = true
        if isLoaded { scheduleAutosave(.pinned) }
        return true
    }

    @discardableResult
    func updateDaily(_ candidate: String, byteCount: Int? = nil) -> Bool {
        guard valid(candidate, byteCount: byteCount) else { return false }
        guard candidate != dailyText else { return true }
        dailyText = candidate
        hasDailyLocalEdits = true
        if isLoaded { scheduleAutosave(.daily(selectedDateIdentifier)) }
        return true
    }

    func waitUntilLoaded() async {
        await loadTask?.value
    }

    func waitUntilIndexed() async {
        await indexTask?.value
    }

    func searchNotes(_ query: String) async -> [HyperliteNoteSearchResult] {
        await searchIndex.search(query)
    }

    func displayName(for identifier: String) -> String {
        guard let date = HyperliteNoteDate.date(from: identifier, calendar: calendar) else {
            return identifier
        }
        let day = calendar.component(.day, from: date)
        let monthIndex = calendar.component(.month, from: date) - 1
        let year = calendar.component(.year, from: date)
        let ordinal = Self.ordinalFormatter.string(from: NSNumber(value: day)) ?? String(day)
        let month = Self.monthNames.indices.contains(monthIndex)
            ? Self.monthNames[monthIndex]
            : String(monthIndex + 1)
        return "\(month) \(ordinal), \(year)"
    }

    func selectDateIdentifier(_ identifier: String, focus: Bool = false) async {
        guard let date = HyperliteNoteDate.date(from: identifier, calendar: calendar) else {
            errorMessage = HyperliteNotepadError.invalidDate(identifier).localizedDescription
            return
        }
        await selectDate(date, focus: focus)
    }

    func selectDate(_ candidate: Date, focus: Bool = false) async {
        let target = calendar.startOfDay(for: candidate)
        let identifier = HyperliteNoteDate.identifier(for: target, calendar: calendar)
        activeTab = .daily
        guard identifier != selectedDateIdentifier else {
            if focus { requestFocus(.daily) }
            return
        }
        guard !isNavigating else { return }
        isNavigating = true
        defer { isNavigating = false }
        guard await flush(.daily(selectedDateIdentifier)) else { return }
        do {
            let document = try await client.loadDaily(date: identifier)
            guard document.content.utf8.count <= Self.maxBytes else {
                throw HyperliteNotepadError.tooLarge
            }
            selectedDate = target
            savedDailyText = document.content
            dailyText = document.content
            hasDailyLocalEdits = false
            errorMessage = nil
            if document.exists { updateIndex(with: document) }
            if focus { requestFocus(.daily) }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func focusPinned() {
        activeTab = .notepad
        requestFocus(.pinned)
    }

    func focusDaily() {
        activeTab = .daily
        requestFocus(.daily)
    }

    @discardableResult
    func flush() async -> Bool {
        autosaveTasks.values.forEach { $0.cancel() }
        autosaveTasks.removeAll()
        await loadTask?.value
        let pinnedSaved = await flush(.pinned)
        let dailySaved = await flush(.daily(selectedDateIdentifier))
        return pinnedSaved && dailySaved
    }

    private func loadInitialDocuments() async {
        var observedError: Error?
        do {
            let document = try await client.loadPinned()
            guard document.content.utf8.count <= Self.maxBytes else {
                throw HyperliteNotepadError.tooLarge
            }
            savedPinnedText = document.content
            if !hasPinnedLocalEdits { pinnedText = document.content }
        } catch is CancellationError {
            return
        } catch {
            observedError = error
        }
        do {
            let document = try await client.loadDaily(date: selectedDateIdentifier)
            guard document.content.utf8.count <= Self.maxBytes else {
                throw HyperliteNotepadError.tooLarge
            }
            savedDailyText = document.content
            if !hasDailyLocalEdits { dailyText = document.content }
        } catch is CancellationError {
            return
        } catch {
            observedError = error
        }
        errorMessage = observedError?.localizedDescription
        isLoaded = true
        loadTask = nil
        if isDirty {
            scheduleAutosave(.pinned)
            scheduleAutosave(.daily(selectedDateIdentifier))
        }
    }

    private func buildSearchIndex() async {
        defer { indexTask = nil }
        do {
            var documents = Dictionary(
                uniqueKeysWithValues: try await client.indexDocuments().map { ($0.id, $0) }
            )
            guard !Task.isCancelled else { return }
            pendingIndexDocuments.forEach { documents[$0.key] = $0.value }
            pendingIndexDocuments.removeAll()
            await searchIndex.replace(with: Array(documents.values))
            isIndexReady = true
            let trailingDocuments = Array(pendingIndexDocuments.values)
            pendingIndexDocuments.removeAll()
            for document in trailingDocuments {
                _ = await searchIndex.upsert(document)
            }
            if errorMessage == indexErrorMessage { errorMessage = nil }
            indexErrorMessage = nil
            searchIndexRevision += 1
        } catch is CancellationError {
            return
        } catch {
            indexErrorMessage = error.localizedDescription
            errorMessage = indexErrorMessage
            pendingIndexDocuments.removeAll()
        }
    }

    func rebuildSearchIndex() {
        guard indexTask == nil, !isIndexReady else { return }
        indexTask = Task { [weak self] in await self?.buildSearchIndex() }
    }

    private func valid(_ content: String, byteCount: Int?) -> Bool {
        guard (byteCount ?? content.utf8.count) <= Self.maxBytes else {
            errorMessage = HyperliteNotepadError.tooLarge.localizedDescription
            return false
        }
        return true
    }

    private func requestFocus(_ target: HyperliteNotepadFocusRequest.Target) {
        focusGeneration += 1
        focusRequest = HyperliteNotepadFocusRequest(target: target, generation: focusGeneration)
    }

    func updateIndex(with document: HyperliteNoteDocument) {
        guard isIndexReady else {
            pendingIndexDocuments[document.id] = document
            if indexTask == nil { rebuildSearchIndex() }
            return
        }
        indexUpdateTask?.cancel()
        indexUpdateTask = Task { [weak self, searchIndex] in
            _ = await searchIndex.upsert(document)
            guard !Task.isCancelled else { return }
            self?.searchIndexRevision += 1
        }
    }

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .ordinal
        return formatter
    }()

    private static let monthNames: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.monthSymbols
    }()
}
