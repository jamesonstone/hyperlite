import Foundation

struct HyperlitePullRequestRowLayout: Equatable {
    let repositoryColumnWidth: CGFloat
    let reviewFeedbackColumnWidth: CGFloat
    let mergeConflictColumnWidth: CGFloat
    let availabilityMetadataColumnWidth: CGFloat
    let repositoryLayoutPriority: Double
    let metadataLayoutPriority: Double
    let titleLayoutPriority: Double

    static let repositoryFirst = HyperlitePullRequestRowLayout(
        repositoryColumnWidth: 190,
        reviewFeedbackColumnWidth: 28,
        mergeConflictColumnWidth: 16,
        availabilityMetadataColumnWidth: 149,
        repositoryLayoutPriority: 1,
        metadataLayoutPriority: 2,
        titleLayoutPriority: -1
    )

    static let titleFirst = HyperlitePullRequestRowLayout(
        repositoryColumnWidth: 148,
        reviewFeedbackColumnWidth: 28,
        mergeConflictColumnWidth: 16,
        availabilityMetadataColumnWidth: 149,
        repositoryLayoutPriority: -1,
        metadataLayoutPriority: 2,
        titleLayoutPriority: 1
    )

    /// Review toggle plus the row HStack spacing before `#number` / title.
    /// Section labels and chips indent to this column.
    static let rowChromeLeading: CGFloat = 20 + 4
}
