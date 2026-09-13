import SwiftUI

/// A small family of rounded line icons, drawn on the same 24-point grid.
struct LoreGlyph: View {
    enum Kind { case today, timeline, projects, pulse, appearance, sources, privacy, diagnostics }
    let kind: Kind
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            var p = Path()
            func line(_ points: [(CGFloat, CGFloat)]) {
                guard let first = points.first else { return }
                p.move(to: CGPoint(x: first.0 * scale, y: first.1 * scale))
                for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.0 * scale, y: point.1 * scale)) }
            }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 2) {
                p.addRoundedRect(in: CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale), cornerSize: CGSize(width: r * scale, height: r * scale))
            }
            switch kind {
            case .pulse: line([(2,13),(6,13),(9,5),(12,20),(15,9),(18,13),(22,13)])
            case .today:
                rect(3,5,18,16); line([(3,10),(21,10)]); line([(8,3),(8,7)]); line([(16,3),(16,7)])
                rect(7,14,3,3,0.6); rect(14,14,3,3,0.6)
            case .timeline:
                line([(6,3),(6,21)]); line([(11,6),(21,6)]); line([(11,12),(18,12)]); line([(11,18),(21,18)])
                for y in [6,12,18] { p.addEllipse(in: CGRect(x: 4 * scale, y: CGFloat(y-2) * scale, width: 4 * scale, height: 4 * scale)) }
            case .projects:
                line([(3,20),(3,5),(10,5),(13,8),(21,8),(21,20),(3,20)]); line([(3,11),(21,11)])
            case .appearance:
                p.addEllipse(in: CGRect(x: 4 * scale, y: 4 * scale, width: 16 * scale, height: 16 * scale)); line([(12,4),(12,20)])
                line([(15,7),(17,9)]); line([(15,12),(18,15)])
            case .sources:
                rect(3,8,7,8,3); rect(14,8,7,8,3); line([(9,12),(15,12)])
            case .privacy:
                line([(12,3),(20,6),(19,15),(16,19),(12,22),(8,19),(5,15),(4,6),(12,3)])
                line([(8,12),(11,15),(16,9)])
            case .diagnostics:
                line([(4,20),(4,12)]); line([(12,20),(12,4)]); line([(20,20),(20,8)])
            }
            context.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round))
        }.frame(width: 21, height: 21).accessibilityHidden(true)
    }
}
