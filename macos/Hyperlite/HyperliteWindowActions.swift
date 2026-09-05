import AppKit
import SwiftUI

extension HyperliteWindow {
    var projectRemovalConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingProjectRemoval != nil },
            set: { if !$0 { pendingProjectRemoval = nil } }
        )
    }

    func handlePaletteAction(_ action: HyperlitePaletteAction) {
        if action == .chooseProjectToRemove {
            state.showPalette(.removeProjects)
            return
        }
        if action == .copyOpenPRMergePrompt {
            copyVisibleOpenPRMergePrompt()
            return
        }
        state.dismissPalette()
        switch action {
        case .showDashboard:
            state.showWorkspace(.dashboard)
        case .showPinboard:
            state.showWorkspace(.pinboard)
        case .showSessions:
            state.showWorkspace(.sessions)
        case .addPinboardNote:
            state.showWorkspace(.pinboard)
            pinboard.request(.addNote)
        case .addPinboardSection:
            state.showWorkspace(.pinboard)
            pinboard.request(.addSection)
        case .openPinboardArchive:
            state.showWorkspace(.pinboard)
            pinboard.request(.openArchive)
        case .refresh:
            state.refreshAll()
        case .forceCacheRefresh:
            state.forceCacheRefresh()
        case .copyOpenPRMergePrompt:
            break
        case .settings:
            openHyperliteSettings()
        case .addProject:
            guard let path = HyperliteProjectPicker.selectProject() else { return }
            state.addProject(path: path)
        case .chooseProjectToRemove:
            break
        case let .removeProject(path):
            pendingProjectRemoval = configuredProjects.first { $0.path == path }
        case let .reveal(threadID):
            selectedThread = state.activeThreads().first { $0.id == threadID }
        case let .openPullRequest(rawURL):
            guard let url = URL(string: rawURL) else { return }
            NSWorkspace.shared.open(url)
        case let .revealPath(path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .focusPinnedNote:
            notepad.focusPinned()
        case let .openDailyNote(date):
            Task { await notepad.selectDateIdentifier(date, focus: true) }
        }
    }

    func copyVisibleOpenPRMergePrompt() {
        let rows = visibleOpenPullRequests
        guard !rows.isEmpty else { return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(
            HyperliteOpenPRMergePrompt.text(rows: rows),
            forType: .string
        ) else { return }
        mergePromptCopyGeneration += 1
    }
}
