import AppKit
import SwiftUI

let defaultHotKey = "Control+Shift+H"

func openHyperliteSettings() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}

@main
struct HyperliteApp: App {
    @NSApplicationDelegateAdaptor(HyperliteApplicationDelegate.self) private var applicationDelegate
    @StateObject private var state = HyperliteState.shared

    var body: some Scene {
        WindowGroup("Hyperlite", id: "hyperlite") {
            HyperliteWindow(state: state)
        }
        .defaultSize(width: 480, height: 650)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            HyperliteMenu(state: state)
        } label: {
            HyperliteMenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            HyperliteSettingsView()
        }
    }
}
