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
    @StateObject private var pinnedCodexThreads = HyperlitePinnedCodexThreadState.shared

    var body: some Scene {
        WindowGroup("Hyperlite", id: "hyperlite") {
            HyperliteWindow(
                state: state,
                pinnedCodexThreads: pinnedCodexThreads,
                notepad: HyperliteNotepadState.shared
            )
                .font(HyperliteTypography.regular(13))
                .background(HyperliteSettingsActionInstaller())
                .hyperliteTheme()
        }
        .defaultSize(width: 480, height: 650)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Navigate") {
                Button("Refresh") { state.refreshAll() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Command Palette") { state.showPalette(.commands) }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Project Palette") { state.showPalette(.projects) }
                    .keyboardShortcut("p", modifiers: .command)
            }
        }

        MenuBarExtra {
            HyperliteMenu(state: state)
                .font(HyperliteTypography.regular(13))
        } label: {
            HyperliteMenuBarLabel(state: state)
                .font(HyperliteTypography.regular(13))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            HyperliteSettingsView(state: state)
                .font(HyperliteTypography.regular(13))
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
