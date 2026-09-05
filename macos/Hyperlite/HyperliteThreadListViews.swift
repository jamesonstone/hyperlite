import AppKit
import SwiftUI

struct HyperliteSettingsView: View {
    @ObservedObject var state: HyperliteState
    @AppStorage("hyperlite.hotkey") private var hotkey = defaultHotKey

    var body: some View {
        Form {
            Section("Shortcut") {
                TextField("Hot key", text: $hotkey)
                Text("Default: \(defaultHotKey). Use modifier names joined with +, for example Command+Shift+H.")
                    .font(HyperliteTypography.regular(11))
                    .foregroundStyle(HyperliteTheme.secondaryText.color)
            }
            Section("Projects") {
                Button("Add Project…") {
                    guard let path = HyperliteProjectPicker.selectProject() else { return }
                    state.addProject(path: path)
                }
                .disabled(state.isUpdatingProjects)
                if state.isUpdatingProjects {
                    ProgressView("Updating project configuration…")
                        .controlSize(.small)
                }
                if let error = state.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(HyperliteTypography.regular(10))
                        .foregroundStyle(HyperliteTheme.red.color)
                        .lineLimit(2)
                        .help(error)
                }
            }
            Section {
                Button("Quit Hyperlite") { NSApp.terminate(nil) }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
    }
}
