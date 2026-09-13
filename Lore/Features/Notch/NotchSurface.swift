import SwiftUI

/// Fixed opaque SDR black for every surface adjoining the physical camera cutout.
/// Transparency is only used outside the rounded silhouette, never inside it.
enum NotchSurface {
    static let black = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
}

/// Morph the path itself. Its top edge remains at y = 0 throughout interpolation;
/// animating a SwiftUI frame would also interpolate its layout position.
struct GrowingNotchSurface: Shape {
    var surfaceWidth: CGFloat
    var surfaceHeight: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(surfaceWidth, surfaceHeight) }
        set { surfaceWidth = newValue.first; surfaceHeight = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let width = max(0, surfaceWidth), height = max(0, surfaceHeight)
        let left = rect.midX - width / 2, right = rect.midX + width / 2
        let top = rect.minY, bottom = top + height
        let radius = min(20, min(width, height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - radius), control: CGPoint(x: left, y: bottom))
        path.closeSubpath()
        return path
    }
}
