import SwiftUI

/// A curved, off-axis spark with a small satellite. Shared by the UI, menu bar and app icon.
struct LoreSpark: Shape {
    var motionPhase: Double = 0
    var energy: Double = 0
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(motionPhase, energy) }
        set { motionPhase = newValue.first; energy = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func inset(_ branch: Double) -> CGFloat {
            CGFloat(max(0, min(1, energy)) * 0.12 * (0.5 + 0.5 * sin(motionPhase - branch * .pi / 2)))
        }
        path.move(to: point(0.57, 0.03 + inset(0)))
        path.addCurve(to: point(0.93 - inset(1), 0.55), control1: point(0.57, 0.36), control2: point(0.63, 0.48))
        path.addCurve(to: point(0.39, 0.97 - inset(2)), control1: point(0.60, 0.55), control2: point(0.45, 0.63))
        path.addCurve(to: point(0.03 + inset(3), 0.45), control1: point(0.40, 0.65), control2: point(0.32, 0.52))
        path.addCurve(to: point(0.57, 0.03 + inset(0)), control1: point(0.34, 0.43), control2: point(0.51, 0.35))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.08,
                                  width: rect.width * 0.09, height: rect.height * 0.09))
        return path
    }
}

@MainActor enum LorePalette {
    static var accent: Color { LorePreferences.shared.accent.color }
    static let secondary = Color(red: 0.37, green: 0.61, blue: 0.78)
    static var colors: [Color] { [accent, secondary, .teal, .orange, .pink] }
}

struct LoreMark: View {
    var body: some View {
        LoreSpark().fill(LorePalette.accent.gradient).accessibilityHidden(true)
    }
}

@MainActor enum LoreMenuIcon {
    static var image: NSImage {
        let renderer = ImageRenderer(content: LoreSpark().fill(.black).frame(width: 18, height: 18))
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Lore")!
        image.isTemplate = true
        return image
    }
}
