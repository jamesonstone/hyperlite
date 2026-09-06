import AppKit
import SwiftUI

let defaultHotKey = "Control+Shift+H"

@available(macOS 14.0, *)
@MainActor
private var settingsWindowAction: OpenSettingsAction?

@MainActor
func openHyperliteSettings() {
    if #available(macOS 14.0, *) {
        settingsWindowAction?()
    } else {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

@main
struct HyperliteApp: App {
    @NSApplicationDelegateAdaptor(HyperliteApplicationDelegate.self) private var applicationDelegate
    @StateObject private var state = HyperliteState.shared

    var body: some Scene {
        WindowGroup(HyperliteWindowChrome.title, id: "hyperlite") {
            HyperliteWindow(
                state: state,
                notepad: HyperliteNotepadState.shared
            )
                .font(HyperliteTypography.chrome)
                .background(HyperliteSettingsActionInstaller())
                .hyperliteTheme()
        }
        .defaultSize(width: 560, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Navigate") {
                Button("Refresh") { state.refreshAll() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Update Default Branches") { state.updateDefaultBranches() }
                Button("Sweep Worktrees") {
                    do {
                        try HyperliteGitMaintenance.startSweep()
                    } catch {
                        state.presentError(error.localizedDescription)
                    }
                }
                Divider()
                Button("Command Palette") { state.showPalette(.commands) }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Project Palette") { state.showPalette(.projects) }
                    .keyboardShortcut("p", modifiers: .command)
            }
        }

        Settings {
            HyperliteSettingsView(state: state)
                .font(HyperliteTypography.chrome)
                .hyperliteTheme()
        }
    }
}

private struct HyperliteSettingsActionInstaller: View {
    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                HyperliteSettingsActionBridge()
            }
        }
    }
}

@available(macOS 14.0, *)
private struct HyperliteSettingsActionBridge: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .onAppear { settingsWindowAction = openSettings }
    }
}
