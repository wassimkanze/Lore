import SwiftUI
import AppKit

struct NotchHoverRegion: Equatable {
    let id: String
    /// Coordinates from the top-left of the content, matching SwiftUI layout.
    let rect: CGRect
}

/// The island is deliberately never a key window. Track the mouse explicitly with
/// activeAlways areas, so hover does not depend on SwiftUI's key-window tracking.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onRegionHover: ((String?) -> Void)?
    var onPanelHover: ((Bool) -> Void)?
    private var regions: [NotchHoverRegion] = []
    private var ownedAreas: [NSTrackingArea] = []
    private var hoveredRegion: String?
    private var inside = false
    private var trackedBounds = CGRect.null

    func configure(regions: [NotchHoverRegion], tracksPanel: Bool) {
        guard self.regions != regions || (onPanelHover != nil) != tracksPanel || trackedBounds != bounds else { return }
        self.regions = regions
        rebuildAreas(tracksPanel: tracksPanel)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackedBounds != bounds { rebuildAreas(tracksPanel: onPanelHover != nil) }
    }
    private func rebuildAreas(tracksPanel: Bool) {
        for area in ownedAreas { removeTrackingArea(area) }
        ownedAreas.removeAll(); trackedBounds = bounds
        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .enabledDuringMouseDrag]
        for region in regions {
            var rect = region.rect
            if !isFlipped { rect.origin.y = bounds.height - rect.maxY }
            let area = NSTrackingArea(rect: rect, options: options, owner: self, userInfo: ["loreRegion": region.id])
            addTrackingArea(area); ownedAreas.append(area)
        }
        if tracksPanel {
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: ["lorePanel": true])
            addTrackingArea(area); ownedAreas.append(area)
        }
    }
    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea?.userInfo?["loreRegion"] != nil || event.trackingArea?.userInfo?["lorePanel"] != nil {
            synchronizeHover()
        } else { super.mouseEntered(with: event) }
    }
    override func mouseExited(with event: NSEvent) {
        if event.trackingArea?.userInfo?["loreRegion"] != nil || event.trackingArea?.userInfo?["lorePanel"] != nil {
            synchronizeHover()
        } else { super.mouseExited(with: event) }
    }
    func synchronizeHover(reportPanelState: Bool = false) {
        guard let window, window.isVisible else { return }
        let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let isInside = bounds.contains(local)
        if inside != isInside || (reportPanelState && isInside) { inside = isInside; onPanelHover?(isInside) }
        let point = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        let region = isInside ? regions.first { $0.rect.contains(point) }?.id : nil
        if hoveredRegion != region { hoveredRegion = region; onRegionHover?(region) }
    }
}
