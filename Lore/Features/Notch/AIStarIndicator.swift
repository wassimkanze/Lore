import SwiftUI

/// Same silhouette as Lore's identity, with a wave travelling through its four branches.
struct AIStarGlyph: View {
    let summary: LiveActivitySummary
    let phase: Double
    var body: some View {
        ZStack {
            if summary.phase == .completed {
                Image(systemName: "checkmark").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(red: 0.64, green: 0.92, blue: 0.75))
                    .transition(.scale(scale: 0.75).combined(with: .opacity))
            } else {
                let energy = summary.workingCount > 0 ? min(0.9, 0.55 + Double(summary.workingCount) * 0.09) : 0
                LoreSpark(motionPhase: phase, energy: energy)
                    .fill(.white.opacity(summary.phase == nil ? 0.38 : summary.phase == .uncertain ? 0.48 : 0.94))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }.frame(width: 25, height: 25)
            .overlay(alignment: .topTrailing) {
                if summary.activeCount > 1 {
                    Text(summary.activeCount > 99 ? "99+" : "\(summary.activeCount)")
                        .font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 3).frame(minHeight: 12).background(.white, in: Capsule())
                        .overlay { Capsule().stroke(.black, lineWidth: 1) }
                        .offset(x: 7, y: -3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if summary.phase == .needsInput || summary.phase == .stopped || summary.phase == .uncertain {
                    Image(systemName: summary.phase == .needsInput ? "exclamationmark" : summary.phase == .stopped ? "xmark" : "minus")
                        .font(.system(size: 7, weight: .heavy)).foregroundStyle(.black)
                        .frame(width: 12, height: 12)
                        .background(summary.phase == .needsInput ? Color.orange : summary.phase == .stopped ? .red : .gray, in: Circle())
                        .overlay { Circle().stroke(.black, lineWidth: 1.5) }.offset(x: 5, y: 2)
                }
            }
            .accessibilityHidden(true)
    }
}

struct AIStarIndicator: View {
    let summary: LiveActivitySummary
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || LorePreferences.shared.reduceMotion }
    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || summary.workingCount == 0)) { timeline in
            let period = summary.workingCount > 1 ? 1.8 : 2.8
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * 2 * .pi
            AIStarGlyph(summary: summary, phase: phase)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: summary.phase)
        }
    }
}
