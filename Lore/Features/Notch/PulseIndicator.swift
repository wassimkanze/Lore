import SwiftUI

/// Visual rhythms for Pulse: resting, awake, and confirmed lid-closed activity.
enum PulseRhythm: CaseIterable {
    case resting, awake, closedLidConfirmed
    var cyclesPerSecond: Double {
        switch self { case .resting: 1 / 2.4; case .awake: 1 / 1.2; case .closedLidConfirmed: 1 / 0.8 }
    }
    var color: Color {
        switch self {
        case .resting: Color(white: 0.60)
        case .awake: Color(white: 0.98)
        case .closedLidConfirmed: Color(red: 0.77, green: 0.70, blue: 1)
        }
    }
}

/// A small scrolling ECG-like trace, also used for deterministic development renders.
struct PulseTrace: View {
    let rhythm: PulseRhythm
    let phase: Double
    var tint: Color? = nil
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let samples = 120
            for index in 0...samples {
                let x = Double(index) / Double(samples)
                let signal = Self.signal(at: x * 1.45 + phase)
                let point = CGPoint(x: x * size.width, y: size.height * (0.55 - signal * 0.39))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let gradient = Gradient(stops: [
                .init(color: (tint ?? rhythm.color).opacity(0.12), location: 0),
                .init(color: tint ?? rhythm.color, location: 0.25),
                .init(color: tint ?? rhythm.color, location: 0.82),
                .init(color: (tint ?? rhythm.color).opacity(0.18), location: 1)
            ])
            let ink = GraphicsContext.Shading.linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
            context.stroke(path, with: ink, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
    private static func signal(at position: Double) -> Double {
        let t = position - floor(position)
        func bump(_ center: Double, _ width: Double, _ amplitude: Double) -> Double {
            let distance = (t - center) / width
            return amplitude * exp(-distance * distance / 2)
        }
        return bump(0.15, 0.038, 0.10) - bump(0.36, 0.021, 0.19)
            + bump(0.42, 0.018, 1.0) - bump(0.48, 0.024, 0.42) + bump(0.68, 0.066, 0.19)
    }
}

private struct PulseClock {
    var anchor: TimeInterval
    var phase: Double
    var fromRate: Double
    var toRate: Double
    private let transition: TimeInterval = 0.45
    init(rhythm: PulseRhythm) {
        let now = ProcessInfo.processInfo.systemUptime
        anchor = now; fromRate = rhythm.cyclesPerSecond; toRate = fromRate
        phase = (now * fromRate).truncatingRemainder(dividingBy: 1)
    }
    func value(at now: TimeInterval) -> Double {
        let elapsed = max(0, now - anchor)
        let ramp = min(elapsed, transition)
        let s = ramp / transition
        // Integral of smoothstep: smoothly accelerate without jumping the waveform.
        let integral = transition * (s * s * s - 0.5 * s * s * s * s)
        return phase + fromRate * ramp + (toRate - fromRate) * integral + max(0, elapsed - transition) * toRate
    }
    mutating func setRhythm(_ rhythm: PulseRhythm) {
        let now = ProcessInfo.processInfo.systemUptime
        let nextPhase = value(at: now).truncatingRemainder(dividingBy: 1)
        let s = min(1, max(0, now - anchor) / transition)
        fromRate += (toRate - fromRate) * s * s * (3 - 2 * s)
        toRate = rhythm.cyclesPerSecond; phase = nextPhase; anchor = now
    }
}

struct PulseIndicator: View {
    let rhythm: PulseRhythm
    let tint: Color?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || LorePreferences.shared.reduceMotion }
    @State private var clock: PulseClock
    init(rhythm: PulseRhythm, tint: Color? = nil) {
        self.tint = tint
        self.rhythm = rhythm
        _clock = State(initialValue: PulseClock(rhythm: rhythm))
    }
    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { _ in
            PulseTrace(rhythm: rhythm, phase: reduceMotion ? 0.18 : clock.value(at: ProcessInfo.processInfo.systemUptime), tint: tint)
        }
        .onChange(of: rhythm) { _, newValue in clock.setRhythm(newValue) }
        .frame(width: 32, height: 20)
        .accessibilityHidden(true)
    }
}

#Preview("Pulse rhythms — development preview, not live power state") {
    VStack(spacing: 24) {
        ForEach(Array(PulseRhythm.allCases.enumerated()), id: \.offset) { _, rhythm in
            PulseIndicator(rhythm: rhythm)
        }
    }.padding(24).background(.black)
}
