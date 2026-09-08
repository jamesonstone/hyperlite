import SwiftUI

struct HyperliteWorkspacePanes<PullRequests: View, Notepad: View>: View {
    let verticalMode: Bool
    let stackedFraction: Double
    let verticalFraction: Double
    let onStackedFraction: (Double) -> Void
    let onVerticalFraction: (Double) -> Void
    let onResetStacked: () -> Void
    let onResetVertical: () -> Void
    let stackedContentHeight: CGFloat
    let pullRequests: PullRequests
    let notepad: Notepad

    @State private var dragOrigin: Double?
    @State private var stackedDragStartedFromFit = false
    @State private var liveStackedFraction: Double?
    @State private var liveVerticalFraction: Double?

    init(
        verticalMode: Bool,
        stackedFraction: Double,
        verticalFraction: Double,
        onStackedFraction: @escaping (Double) -> Void,
        onVerticalFraction: @escaping (Double) -> Void,
        onResetStacked: @escaping () -> Void,
        onResetVertical: @escaping () -> Void,
        stackedContentHeight: CGFloat,
        @ViewBuilder pullRequests: () -> PullRequests,
        @ViewBuilder notepad: () -> Notepad
    ) {
        self.verticalMode = verticalMode
        self.stackedFraction = stackedFraction
        self.verticalFraction = verticalFraction
        self.onStackedFraction = onStackedFraction
        self.onVerticalFraction = onVerticalFraction
        self.onResetStacked = onResetStacked
        self.onResetVertical = onResetVertical
        self.stackedContentHeight = stackedContentHeight
        self.pullRequests = pullRequests()
        self.notepad = notepad()
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing = HyperliteWorkspaceSizing.sectionSpacing
            if verticalMode {
                horizontalSplit(size: geometry.size, spacing: spacing)
            } else {
                stackedSplit(size: geometry.size, spacing: spacing)
            }
        }
    }

    private var effectiveStackedFraction: Double {
        liveStackedFraction ?? stackedFraction
    }

    private var effectiveVerticalFraction: Double {
        liveVerticalFraction ?? verticalFraction
    }

    private func stackedSplit(size: CGSize, spacing: CGFloat) -> some View {
        let pullHeight = HyperliteWorkspaceSplit.stackedPullRequestHeight(
            fraction: effectiveStackedFraction,
            contentHeight: stackedContentHeight,
            containerHeight: size.height
        )
        return VStack(alignment: .leading, spacing: spacing) {
            pullRequests
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(height: pullHeight, alignment: .topLeading)
                .clipped()
            HyperliteWorkspaceSplitter(
                axis: .vertical,
                onDrag: { translation in
                    applyStackedDrag(translation: translation, containerHeight: size.height)
                },
                onEnd: commitStackedDrag,
                onReset: resetStacked
            )
            notepad
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func horizontalSplit(size: CGSize, spacing: CGFloat) -> some View {
        let pullWidth = HyperliteWorkspaceSplit.verticalPullRequestWidth(
            fraction: effectiveVerticalFraction,
            containerWidth: size.width
        )
        return HStack(alignment: .top, spacing: spacing) {
            pullRequests
                .frame(width: pullWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            HyperliteWorkspaceSplitter(
                axis: .horizontal,
                onDrag: { translation in
                    applyVerticalDrag(translation: translation, containerWidth: size.width)
                },
                onEnd: commitVerticalDrag,
                onReset: resetVertical
            )
            notepad
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func applyStackedDrag(translation: CGFloat, containerHeight: CGFloat) {
        let fitDisplayed = HyperliteWorkspaceSplit.displayedStackedFraction(
            fraction: HyperliteWorkspaceSplit.fitContent,
            contentHeight: stackedContentHeight,
            containerHeight: containerHeight
        )
        if dragOrigin == nil {
            stackedDragStartedFromFit = stackedFraction <= HyperliteWorkspaceSplit.fitContent
            dragOrigin = HyperliteWorkspaceSplit.displayedStackedFraction(
                fraction: stackedFraction,
                contentHeight: stackedContentHeight,
                containerHeight: containerHeight
            )
        }
        liveStackedFraction = HyperliteWorkspaceSplit.liveStackedFraction(
            origin: dragOrigin ?? fitDisplayed,
            translation: translation,
            container: containerHeight,
            startedFromFit: stackedDragStartedFromFit,
            fitDisplayed: fitDisplayed
        )
    }

    private func applyVerticalDrag(translation: CGFloat, containerWidth: CGFloat) {
        if dragOrigin == nil {
            dragOrigin = verticalFraction <= HyperliteWorkspaceSplit.fitContent
                ? HyperliteWorkspaceSplit.defaultVerticalFraction
                : HyperliteWorkspaceSplit.clamped(verticalFraction)
        }
        liveVerticalFraction = HyperliteWorkspaceSplit.clamped(
            (dragOrigin ?? HyperliteWorkspaceSplit.defaultVerticalFraction)
                + HyperliteWorkspaceSplit.fractionDelta(
                    translation: translation,
                    container: containerWidth
                )
        )
    }

    private func commitStackedDrag() {
        if let liveStackedFraction {
            onStackedFraction(
                HyperliteWorkspaceSplit.persistedStackedFraction(
                    live: liveStackedFraction,
                    origin: dragOrigin ?? liveStackedFraction,
                    startedFromFit: stackedDragStartedFromFit
                )
            )
        }
        dragOrigin = nil
        stackedDragStartedFromFit = false
        liveStackedFraction = nil
    }

    private func commitVerticalDrag() {
        if let liveVerticalFraction {
            onVerticalFraction(liveVerticalFraction)
        }
        dragOrigin = nil
        liveVerticalFraction = nil
    }

    private func resetStacked() {
        dragOrigin = nil
        stackedDragStartedFromFit = false
        liveStackedFraction = nil
        onResetStacked()
    }

    private func resetVertical() {
        dragOrigin = nil
        liveVerticalFraction = nil
        onResetVertical()
    }
}
