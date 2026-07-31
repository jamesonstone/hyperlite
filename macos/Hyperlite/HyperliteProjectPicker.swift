import AppKit

@MainActor
enum HyperliteProjectPicker {
    static func selectProject() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Add a Project"
        panel.message = "Choose a Git repository root to add to Hyperlite."
        panel.prompt = "Add Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}
