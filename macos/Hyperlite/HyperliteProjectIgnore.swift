import Foundation

extension HyperliteState {
    /// Ignores or re-watches one project. Watching again fetches only that
    /// project at once and expands its section so its pull requests show.
    func toggleIgnored(_ project: HyperliteProjectPullRequests) {
        let ignore = !project.isIgnored
        let path = project.path
        Task { [weak self] in
            do {
                _ = try await HyperliteProcess.run(
                    arguments: ["projects", HyperliteProjectIgnorePresentation.command(ignored: ignore), path],
                    operation: ignore ? "ignore project" : "watch project"
                )
                guard let self else { return }
                if ignore {
                    refreshPullRequests(mode: .local, continueIfStale: false, supersedeExisting: true)
                } else {
                    UserDefaults.standard.set(
                        false,
                        forKey: HyperliteOpenPRProjectSectionPresentation.storageKey(projectID: project.id)
                    )
                    refreshPullRequests(mode: .project(path), continueIfStale: false, supersedeExisting: true)
                }
            } catch {
                self?.presentError(error.localizedDescription)
            }
        }
    }
}
