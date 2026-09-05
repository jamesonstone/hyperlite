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
        case .refresh:
            state.refreshAll()
        case .forceCacheRefresh:
            state.forceCacheRefresh()
        case .copyOpenPRMergePrompt:
            break
        case .updateDefaultBranches:
            state.updateDefaultBranches()
        case .sweepWorktrees:
            do {
                try HyperliteGitMaintenance.startSweep()
            } catch {
                state.presentError(error.localizedDescription)
            }
        case .settings:
            openHyperliteSettings()
        case .addProject:
            guard let path = HyperliteProjectPicker.selectProject() else { return }
            state.addProject(path: path)
        case .chooseProjectToRemove:
            break
        case let .removeProject(path):
            pendingProjectRemoval = state.configuredProjects.first { $0.path == path }
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
