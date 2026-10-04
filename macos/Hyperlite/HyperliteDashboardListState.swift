import Combine
import Foundation

/// Per-operator Open PR state: revision-aware "reviewed by me" marks.
@MainActor
final class HyperliteDashboardListState: ObservableObject {
    @Published private(set) var pullRequestReviewMarks: [String: HyperlitePullRequestReviewMark]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pullRequestReviewMarks = Self.decodePullRequestReviewMarks(defaults: defaults)
    }

    var pullRequestReviewMarkCount: Int { pullRequestReviewMarks.count }

    func pullRequestReviewStatus(
        for row: HyperlitePullRequestRow
    ) -> HyperlitePullRequestReviewStatus {
        HyperlitePullRequestReviewPresentation.status(
            for: row,
            mark: pullRequestReviewMarks[row.reviewID]
        )
    }

    func togglePullRequestReviewed(_ row: HyperlitePullRequestRow, now: Date = Date()) {
        if pullRequestReviewStatus(for: row) == .reviewed {
            pullRequestReviewMarks.removeValue(forKey: row.reviewID)
        } else {
            let headRefOID = row.headRefOID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard row.status == .current, !headRefOID.isEmpty else { return }
            pullRequestReviewMarks[row.reviewID] = HyperlitePullRequestReviewMark(
                repository: row.repository,
                headRefOID: headRefOID,
                markedAt: now
            )
        }
        persistPullRequestReviewMarks()
    }

    func clearPullRequestReviewMarks() {
        guard !pullRequestReviewMarks.isEmpty else { return }
        pullRequestReviewMarks.removeAll()
        persistPullRequestReviewMarks()
    }

    func reconcilePullRequestReviewMarks(scan: HyperliteProjectPullRequestScan) {
        var currentReviewIDs: [String: Set<String>] = [:]
        for project in scan.projects where project.status == .current {
            guard let repository = project.repository else { continue }
            currentReviewIDs[Self.normalizedRepository(repository), default: []]
                .formUnion(project.pullRequests.map(\.id))
        }
        let retained = pullRequestReviewMarks.filter { reviewID, mark in
            guard let current = currentReviewIDs[Self.normalizedRepository(mark.repository)]
            else { return true }
            return current.contains(reviewID)
        }
        guard retained != pullRequestReviewMarks else { return }
        pullRequestReviewMarks = retained
        persistPullRequestReviewMarks()
    }

    private func persistPullRequestReviewMarks() {
        guard let data = try? JSONEncoder().encode(pullRequestReviewMarks) else { return }
        defaults.set(data, forKey: Keys.pullRequestReviewMarks)
    }

    private static func decodePullRequestReviewMarks(
        defaults: UserDefaults
    ) -> [String: HyperlitePullRequestReviewMark] {
        guard let data = defaults.data(forKey: Keys.pullRequestReviewMarks),
              let decoded = try? JSONDecoder().decode(
                  [String: HyperlitePullRequestReviewMark].self,
                  from: data
              )
        else { return [:] }
        return decoded.filter { reviewID, mark in
            !reviewID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !mark.repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !mark.headRefOID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func normalizedRepository(_ repository: String) -> String {
        repository.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private enum Keys {
        static let pullRequestReviewMarks = "hyperlite.dashboard.open-pr-review-marks"
    }
}
