import AppKit
import Foundation

extension HyperliteAgentSessionState {
    func performRoute(_ session: HyperliteAgentSession) {
        if let bundleID = HyperliteAgentRoutePolicy.effectiveBundleID(session.routing) {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate(options: [])
                return
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                    guard let error else { return }
                    Task { @MainActor [weak self] in
                        self?.reportAgentError(error.localizedDescription)
                    }
                }
                return
            }
        }
        if let workspace = session.routing.workspacePath, !workspace.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace)])
            return
        }
        reportAgentError("The owning client could not be resolved.")
    }
}
