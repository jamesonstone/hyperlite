import Foundation

extension HyperliteNotepadState {
    func scheduleAutosave(_ noteID: HyperliteNoteID) {
        autosaveTasks[noteID]?.cancel()
        guard isDirty(noteID) else {
            autosaveTasks[noteID] = nil
            return
        }
        let delay = autosaveDelay
        autosaveTasks[noteID] = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            autosaveTasks[noteID] = nil
            requestSave(noteID)
        }
    }

    func requestSave(_ noteID: HyperliteNoteID) {
        guard isLoaded, isDirty(noteID) else { return }
        guard saveTasks[noteID] == nil else {
            saveQueued.insert(noteID)
            return
        }
        guard let candidate = content(for: noteID) else { return }
        let client = client
        isSaving = true
        saveTasks[noteID] = Task { [weak self] in
            do {
                let document: HyperliteNoteDocument
                switch noteID {
                case .pinned:
                    document = try await client.savePinned(candidate)
                case let .daily(date):
                    document = try await client.saveDaily(date: date, content: candidate)
                }
                self?.finishSave(noteID, candidate: candidate, document: document, error: nil)
            } catch is CancellationError {
                self?.finishSave(noteID, candidate: candidate, document: nil, error: nil, cancelled: true)
            } catch {
                self?.finishSave(noteID, candidate: candidate, document: nil, error: error)
            }
        }
    }

    func finishSave(
        _ noteID: HyperliteNoteID,
        candidate: String,
        document: HyperliteNoteDocument?,
        error: Error?,
        cancelled: Bool = false
    ) {
        if error == nil, !cancelled {
            switch noteID {
            case .pinned:
                savedPinnedText = candidate
            case let .daily(date) where date == selectedDateIdentifier:
                savedDailyText = candidate
            case .daily:
                break
            }
            errorMessage = nil
            if let document { updateIndex(with: document) }
        } else if let error {
            errorMessage = error.localizedDescription
        }
        saveTasks[noteID] = nil
        isSaving = !saveTasks.isEmpty
        let shouldContinue = saveQueued.remove(noteID) != nil && isDirty(noteID) && !cancelled
        if shouldContinue { requestSave(noteID) }
    }

    func flush(_ noteID: HyperliteNoteID) async -> Bool {
        autosaveTasks[noteID]?.cancel()
        autosaveTasks[noteID] = nil
        await saveTasks[noteID]?.value
        if isDirty(noteID) {
            requestSave(noteID)
            await saveTasks[noteID]?.value
        }
        return !isDirty(noteID)
    }

    func isDirty(_ noteID: HyperliteNoteID) -> Bool {
        switch noteID {
        case .pinned:
            pinnedText != savedPinnedText
        case let .daily(date):
            date == selectedDateIdentifier && dailyText != savedDailyText
        }
    }

    func content(for noteID: HyperliteNoteID) -> String? {
        switch noteID {
        case .pinned:
            pinnedText
        case let .daily(date):
            date == selectedDateIdentifier ? dailyText : nil
        }
    }
}
