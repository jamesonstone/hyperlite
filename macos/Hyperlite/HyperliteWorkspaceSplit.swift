import AppKit
import SwiftUI

enum HyperliteWorkspaceSplit {
    static let fitContent: Double = 0
    static let defaultVerticalFraction: Double = 0.36
    static let minFraction: Double = 0.18
    static let maxFraction: Double = 0.72
    static let stackedFitCap: Double = 0.48
    static let stackedFitFallback: Double = 0.28
    static let splitterHit: CGFloat = 8
    static let minimumStackedPullRequestHeight: CGFloat = 72
    static let stackedHeaderHeight: CGFloat = 28
    static let stackedSectionLabelHeight: CGFloat = 16
    static let stackedPinnedLabelTopPadding: CGFloat = 6
    static let stackedActiveSectionTopPadding: CGFloat = 10
    static let stackedIdleSectionTopPadding: CGFloat = 2
    static let stackedEmptyDropHeight: CGFloat = 8
    static let stackedWideRowHeight: CGFloat = 22
    static let stackedCompactRowHeight: CGFloat = 36
    static let stackedEmptyListHeight: CGFloat = 20
    static let stackedPanelSpacing: CGFloat = 8
    static let stackedLazySpacing: CGFloat = 4
    static let stackedStageVerticalPadding: CGFloat = 6
    static let stackedStageSpacing: CGFloat = 8
    static let stackedColumnSpacing: CGFloat = 10
    static let stackedStatusHeight: CGFloat = 20
    static let stackedLoadingHeight: CGFloat = 28
    static let stackedSnapBack: Double = 0.02
    static let splitterMinimumDistance: CGFloat = 8

    static func clamped(_ value: Double) -> Double {
        min(max(value, minFraction), maxFraction)
    }

    static func compactRows(verticalMode: Bool, notesOnly: Bool) -> Bool {
        verticalMode && !notesOnly
    }

    static func stackedPullRequestHeight(
        fraction: Double,
        contentHeight: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        if fraction <= fitContent {
            let cap = max(containerHeight * stackedFitCap, minimumStackedPullRequestHeight)
            let fallback = containerHeight * stackedFitFallback
            let fitted = contentHeight > 0 ? contentHeight : fallback
            return min(max(fitted, minimumStackedPullRequestHeight), cap)
        }
        return max(containerHeight * clamped(fraction), minimumStackedPullRequestHeight)
    }

    static func displayedStackedFraction(
        fraction: Double,
        contentHeight: CGFloat,
        containerHeight: CGFloat
    ) -> Double {
        guard containerHeight > 0 else { return stackedFitFallback }
        return stackedPullRequestHeight(
            fraction: fraction,
            contentHeight: contentHeight,
            containerHeight: containerHeight
        ) / containerHeight
    }

    static func verticalPullRequestWidth(fraction: Double, containerWidth: CGFloat) -> CGFloat {
        let resolved = fraction <= fitContent ? defaultVerticalFraction : clamped(fraction)
        return containerWidth * resolved
    }

    static func fractionDelta(translation: CGFloat, container: CGFloat) -> Double {
        guard container > 0 else { return 0 }
        return Double(translation / container)
    }

    static func liveStackedFraction(
        origin: Double,
        translation: CGFloat,
        container: CGFloat,
        startedFromFit: Bool,
        fitDisplayed: Double
    ) -> Double {
        let raw = origin + fractionDelta(translation: translation, container: container)
        let lower = startedFromFit ? min(fitDisplayed, minFraction) : minFraction
        return min(max(raw, lower), maxFraction)
    }

    static func persistedStackedFraction(
        live: Double,
        origin: Double,
        startedFromFit: Bool
    ) -> Double {
        if startedFromFit && abs(live - origin) < stackedSnapBack {
            return fitContent
        }
        return clamped(live)
    }

    static func summaryTitle(openCount: Int, pinnedCount: Int) -> String {
        "Open PRs \(openCount) · Pinned \(pinnedCount)"
    }

    static func estimatedStackedContentHeight(
        pinnedCount: Int,
        openCount: Int,
        projectSectionCount: Int,
        compactRows: Bool,
        hasStatusMessage: Bool,
        idleProjectCount: Int = 0
    ) -> CGFloat {
        let rowHeight = compactRows ? stackedCompactRowHeight : stackedWideRowHeight
        let rows = pinnedCount + openCount
        var height = stackedHeaderHeight + stackedPanelSpacing
        if rows == 0 && idleProjectCount == 0 {
            height += stackedEmptyListHeight
        } else {
            let emptyDropCount = pinnedCount == 0 ? 1 : 0
            let pinnedStageCount = pinnedCount == 0 ? 0 : 1
            let stageCount = pinnedStageCount + projectSectionCount
            let outerChildCount = emptyDropCount + stageCount
            let nonIdleProjectCount = max(projectSectionCount - idleProjectCount, 0)
            height += stackedStageSpacing * CGFloat(max(outerChildCount - 1, 0))
            if emptyDropCount > 0 { height += stackedEmptyDropHeight }
            if pinnedStageCount > 0 {
                height += stackedStageVerticalPadding * 2
                height += stackedPinnedLabelTopPadding + stackedSectionLabelHeight
                height += CGFloat(pinnedCount) * rowHeight
                height += stackedLazySpacing * CGFloat(pinnedCount)
            }
            height += CGFloat(projectSectionCount) * stackedStageVerticalPadding * 2
            height += stackedSectionLabelHeight * CGFloat(projectSectionCount)
            height += CGFloat(nonIdleProjectCount) * stackedActiveSectionTopPadding
            height += CGFloat(idleProjectCount) * stackedIdleSectionTopPadding
            height += CGFloat(openCount) * rowHeight
            height += stackedLazySpacing * CGFloat(openCount)
        }
        if hasStatusMessage {
            height += stackedStatusHeight + stackedColumnSpacing
        }
        return max(height, minimumStackedPullRequestHeight)
    }
}

struct HyperliteWorkspaceSplitter: View {
    let axis: Axis
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void
    @State private var ignoreDragEnd = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(
                width: axis == .horizontal ? Self.hit : nil,
                height: axis == .vertical ? Self.hit : nil
            )
            .frame(
                maxWidth: axis == .vertical ? .infinity : nil,
                maxHeight: axis == .horizontal ? .infinity : nil
            )
            .overlay {
                Rectangle()
                    .fill(HyperliteTheme.elevatedSurface.color)
                    .frame(
                        width: axis == .horizontal ? 1 : nil,
                        height: axis == .vertical ? 1 : nil
                    )
            }
            .contentShape(Rectangle())
            .onHover(perform: updateCursor)
            .highPriorityGesture(
                TapGesture(count: 2).onEnded {
                    ignoreDragEnd = true
                    onReset()
                }
            )
            .gesture(
                DragGesture(minimumDistance: HyperliteWorkspaceSplit.splitterMinimumDistance)
                    .onChanged { value in
                        onDrag(axis == .vertical ? value.translation.height : value.translation.width)
                    }
                    .onEnded { _ in
                        if ignoreDragEnd {
                            ignoreDragEnd = false
                            return
                        }
                        onEnd()
                    }
            )
            .accessibilityLabel("Resize Open PRs and notes")
            .accessibilityHint("Drag to resize, or adjust. Double-click to restore the default split.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onDrag(Self.keyboardStep)
                case .decrement: onDrag(-Self.keyboardStep)
                @unknown default: return
                }
                onEnd()
            }
    }

    private func updateCursor(_ hovering: Bool) {
        if hovering {
            if axis == .vertical {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.resizeLeftRight.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    private static let hit = HyperliteWorkspaceSplit.splitterHit
    private static let keyboardStep: CGFloat = 24
}
