import Foundation
import CoreGraphics

public struct NotchGeometry: Sendable {
    public let screen: CGRect
    public let visibleFrame: CGRect
    public let cutout: CGRect?
    public init(screen: CGRect, visibleFrame: CGRect, safeTop: CGFloat, leftArea: CGRect, rightArea: CGRect) {
        self.screen = screen; self.visibleFrame = visibleFrame
        if safeTop > 0, !leftArea.isEmpty, !rightArea.isEmpty, rightArea.minX > leftArea.maxX {
            cutout = CGRect(x: leftArea.maxX, y: screen.maxY - safeTop, width: rightArea.minX - leftArea.maxX, height: safeTop)
        } else { cutout = nil }
    }
    public var badgeHeight: CGFloat { cutout.map { min(42, max(28, $0.height)) } ?? 38 }
    public func wing(side: NotchSide, width: CGFloat) -> CGRect? {
        guard let cutout else { return nil }
        let available = side == .right ? screen.maxX - cutout.maxX : cutout.minX - screen.minX
        let width = min(max(0, width), max(0, available - 8))
        return CGRect(x: side == .right ? cutout.maxX : cutout.minX - width,
                      y: screen.maxY - badgeHeight, width: width, height: badgeHeight)
    }
    /// Bridge beneath the camera mask, including its rounded lower corners.
    /// The two backgrounds meet inside the hidden region, not at its visible edges.
    /// Matching inner padding keeps every control at its original screen position.
    public func seamOverlap(backingScale: CGFloat) -> CGFloat {
        (cutout?.width ?? 0) / 2 + 1 / max(1, backingScale)
    }
    public func joinedWing(side: NotchSide, width: CGFloat, backingScale: CGFloat) -> CGRect? {
        guard var frame = wing(side: side, width: width) else { return nil }
        let overlap = seamOverlap(backingScale: backingScale)
        if side == .right { frame.origin.x -= overlap }
        frame.size.width += overlap
        return frame
    }
    public func fallback(width: CGFloat) -> CGRect {
        let width = min(width, max(0, visibleFrame.width - 24))
        return CGRect(x: visibleFrame.midX - width / 2, y: visibleFrame.maxY - badgeHeight - 6, width: width, height: badgeHeight)
    }
}
