import AppKit
import Foundation

struct HyperliteAgentNotchMetrics: Equatable {
    static let fallbackSize = CGSize(width: 190, height: 32)

    let size: CGSize
    let hasPhysicalNotch: Bool

    static func detect(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeftWidth: CGFloat?,
        auxiliaryRightWidth: CGFloat?
    ) -> HyperliteAgentNotchMetrics {
        let height = ceil(safeAreaTop)
        guard height > 0 else {
            return HyperliteAgentNotchMetrics(size: fallbackSize, hasPhysicalNotch: false)
        }
        let left = max(0, auxiliaryLeftWidth ?? 0)
        let right = max(0, auxiliaryRightWidth ?? 0)
        let detectedWidth = left > 0 && right > 0
            ? max(170, ceil(screenFrame.width - left - right + 4))
            : 180
        return HyperliteAgentNotchMetrics(
            size: CGSize(width: detectedWidth, height: height),
            hasPhysicalNotch: true
        )
    }
}

struct HyperliteAgentNotchGeometry: Equatable {
    let screenFrame: CGRect
    let metrics: HyperliteAgentNotchMetrics

    func frame(expanded: Bool, hasSessions: Bool = true) -> CGRect {
        let size = expanded
            ? CGSize(width: 420, height: hasSessions ? 460 : 150)
            : CGSize(width: max(metrics.size.width, 190), height: max(metrics.size.height, 32))
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

extension NSScreen {
    var hyperliteAgentNotchMetrics: HyperliteAgentNotchMetrics {
        HyperliteAgentNotchMetrics.detect(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: auxiliaryTopRightArea?.width
        )
    }
}
