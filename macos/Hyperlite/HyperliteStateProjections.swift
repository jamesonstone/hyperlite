extension HyperliteState {
    var isRefreshing: Bool { isRefreshingThreads || isRefreshingPullRequests }

    func activeThreads() -> [HyperliteThread] {
        guard let scan else { return [] }
        return HyperlitePresentation.activeThreads(scan: scan)
    }

    func attentionThreads() -> [HyperliteThread] {
        guard let scan else { return [] }
        return HyperlitePresentation.attentionThreads(scan: scan)
    }

    func attentionThreadCount() -> Int {
        attentionThreads().count
    }
}
