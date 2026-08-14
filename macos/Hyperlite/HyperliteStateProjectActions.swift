extension HyperliteState {
    func addProject(path: String) {
        updateConfiguredProject(path: path, action: "add")
    }

    func removeProject(path: String) {
        updateConfiguredProject(path: path, action: "remove")
    }
}
